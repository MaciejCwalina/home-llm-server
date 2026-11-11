#!/usr/bin/env bash
# Recreate the home LLM server: 4× RTX 5060 Ti on Ubuntu 24.04, P2P-patched NVIDIA driver,
# vLLM in Docker with FlashInfer PCIe all-reduce and a DFlash2 drafter.
#
# Run the stages in order (each is safe to re-run). Stages that need root use sudo.
#   ./setup.sh host     kernel parameters (IOMMU passthrough), nouveau blacklist, base packages  -> reboot
#   ./setup.sh driver   NVIDIA 615.78.08 userspace + P2P-patched open kernel modules           -> reboot
#   ./setup.sh check    verify driver, BAR size, IOMMU mode and GPU-to-GPU P2P
#   ./setup.sh docker   Docker + NVIDIA container toolkit
#   ./setup.sh models   download the model and the DFlash2 drafter into ~/llm/models
#   ./setup.sh key      generate the API key into ~/llm/vllm.env (never printed)
#   ./setup.sh start    install start-vllm.sh into ~/llm and start the server
#
# The BIOS part can't be scripted. See README.md: UEFI boot (CSM off), Above 4G Decoding, Re-Size BAR.
set -euo pipefail

DRIVER_VERSION=615.78.08
P2P_REPOSITORY=https://github.com/aikitoria/open-gpu-kernel-modules.git
P2P_BRANCH=${DRIVER_VERSION}-p2p
MODEL_REPOSITORY=ajgazin/Swift-Qwen3.8-27B-Uncensored-NVFP4
MODEL_DIRECTORY=swift-qwen3.8-27b-nvfp4
DRAFTER_REPOSITORY=incoai/Qwen3.8-27B-DFlash2
DRAFTER_DIRECTORY=qwen3.8-27b-dflash2
LLM_HOME="$HOME/llm"
SCRIPT_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"

stage_host() {
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq build-essential git curl "linux-headers-$(uname -r)" pciutils python3-venv
    # IOMMU in passthrough mode: required for GPU-to-GPU P2P
    if ! grep -q 'iommu=pt' /etc/default/grub; then
        sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 amd_iommu=on iommu=pt"/' /etc/default/grub
        sudo update-grub
    fi
    printf 'blacklist nouveau\noptions nouveau modeset=0\n' | sudo tee /etc/modprobe.d/blacklist-nouveau.conf >/dev/null
    sudo update-initramfs -u
    echo "host configured: reboot, then run ./setup.sh driver"
}

stage_driver() {
    # Ubuntu's NVIDIA packages would fight the patched modules
    local ubuntu_packages
    ubuntu_packages=$(dpkg -l | awk '/^ii/ && /nvidia/ && !/container/ {print $2}')
    if [ -n "$ubuntu_packages" ]; then
        echo "$ubuntu_packages" | sudo tee /root/nvidia-ubuntu-packages-before-p2p.txt >/dev/null
        # shellcheck disable=SC2086
        sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq $ubuntu_packages
    fi

    local work_directory="$HOME/p2p"
    mkdir -p "$work_directory" && cd "$work_directory"
    local installer="NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run"
    [ -f "$installer" ] || curl -fsSLO "https://download.nvidia.com/XFree86/Linux-x86_64/${DRIVER_VERSION}/${installer}"
    # userspace (libcuda, nvidia-smi, GSP firmware) only; the kernel modules come from the P2P fork
    sudo sh "$installer" --silent --no-kernel-modules --no-x-check --no-nouveau-check --no-systemd --no-questions

    [ -d open-gpu-kernel-modules ] || git clone -q --depth 1 --branch "$P2P_BRANCH" "$P2P_REPOSITORY"
    cd open-gpu-kernel-modules
    make modules -j"$(nproc)"
    sudo make modules_install -j"$(nproc)"
    sudo depmod
    sudo update-initramfs -u
    # The patched modules are not DKMS: a new kernel would boot without a GPU driver.
    sudo apt-mark hold linux-generic linux-image-generic linux-headers-generic
    echo "P2P driver installed: reboot, then run ./setup.sh check"
}

stage_check() {
    nvidia-smi --query-gpu=index,name,driver_version,pcie.link.gen.current,pcie.link.width.current --format=csv
    nvidia-smi -q -d MEMORY | grep -A1 BAR1 | grep Total | head -1
    grep -o 'iommu=pt' /proc/cmdline || echo "WARNING: iommu=pt missing from the kernel command line"
    [ -d /sys/firmware/efi ] && echo "boot mode: UEFI" || echo "WARNING: legacy boot (Re-Size BAR needs UEFI)"
    nvidia-smi topo -p2p r
}

stage_docker() {
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io gnupg
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
        | sudo gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#' \
        | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nvidia-container-toolkit
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
    sudo usermod -aG docker "$USER"
    sudo docker pull vllm/vllm-openai:latest
    echo "docker ready (log out and back in for the docker group to apply)"
}

stage_models() {
    mkdir -p "$LLM_HOME/models" "$LLM_HOME/cache"
    [ -d "$LLM_HOME/.venv" ] || python3 -m venv "$LLM_HOME/.venv"
    "$LLM_HOME/.venv/bin/pip" install -q -U "huggingface_hub[hf_transfer]"
    export HF_HUB_ENABLE_HF_TRANSFER=1
    "$LLM_HOME/.venv/bin/hf" download "$MODEL_REPOSITORY" --local-dir "$LLM_HOME/models/$MODEL_DIRECTORY" --max-workers 16
    "$LLM_HOME/.venv/bin/hf" download "$DRAFTER_REPOSITORY" --local-dir "$LLM_HOME/models/$DRAFTER_DIRECTORY" --max-workers 16
    du -sh "$LLM_HOME/models"/*
}

stage_key() {
    mkdir -p "$LLM_HOME"
    if [ -s "$LLM_HOME/vllm.env" ]; then
        echo "key already exists: $LLM_HOME/vllm.env"
        return
    fi
    (umask 077; printf 'VLLM_API_KEY=%s\n' "$(head -c 48 /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 40)" > "$LLM_HOME/vllm.env")
    echo "API key written to $LLM_HOME/vllm.env (mode 600). Copy it to your clients; it is not printed here."
}

stage_start() {
    install -m 755 "$SCRIPT_DIRECTORY/start-vllm.sh" "$LLM_HOME/start-vllm.sh"
    "$LLM_HOME/start-vllm.sh"
    echo "starting; the first start compiles kernels and takes ~5-8 minutes"
    for _ in $(seq 120); do
        if curl -sf -o /dev/null -H "Authorization: Bearer $(cut -d= -f2- "$LLM_HOME/vllm.env")" localhost:8000/v1/models; then
            echo "vLLM is serving on port 8000"
            docker logs vllm 2>&1 | grep -E 'GPU KV cache size' | tail -1
            return
        fi
        sleep 10
    done
    echo "vLLM did not come up in 20 minutes; check: docker logs vllm" >&2
    return 1
}

case "${1:-}" in
    host|driver|check|docker|models|key|start) "stage_$1" ;;
    *) sed -n '2,15p' "$0"; exit 1 ;;
esac
