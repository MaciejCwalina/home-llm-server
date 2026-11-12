# home-llm-server

How to run **Qwen3.8-27B (NVFP4)** fast on **4× RTX 5060 Ti 16 GB** consumer cards on an old HEDT board (PCIe Gen3).

| | Stock vLLM (TP=4, MTP) | **This setup** |
|---|---|---|
| 1 session | 144 tok/s | **~250 tok/s** |
| 3 sessions (total) | 300 tok/s | **~560 tok/s** |
| 8 sessions (total) | 430 tok/s | **~840 tok/s** |
| Prompt reading (29.5K tokens) | ~815 tok/s | **~2,060 tok/s** |
| KV cache | 773K tokens | **933K tokens** |

Each figure comes from a single run of `bench.py`, so expect ±2–3 % noise. For comparison, one RTX PRO 6000 did 216 tok/s for a single session with the same model and MTP.

## What makes it fast

1. **P2P between GeForce cards.** NVIDIA's open kernel modules with the [aikitoria P2P patch](https://github.com/aikitoria/open-gpu-kernel-modules) (branch `615.78.08-p2p`). With Resizable BAR and IOMMU passthrough, every card pair reaches ~7.1 GB/s directly. That's the Gen3 x8 limit, and it holds even between the two Threadripper dies.
2. **FlashInfer PCIe IPC all-reduce** (`VLLM_ALLREDUCE_USE_FLASHINFER_PCIE_IPC=1`). It replaces NCCL for the tensor-parallel all-reduces and is built for PCIe-only GPUs with P2P. vLLM's own custom all-reduce turns itself off for more than 2 PCIe GPUs; forcing it on made 8 sessions 10 % slower. This change alone took 3 sessions from 300 to 438 tok/s and doubled prefill.
3. **DFlash2 speculative decoding** ([incoai/Qwen3.8-27B-DFlash2](https://huggingface.co/incoai/Qwen3.8-27B-DFlash2)) instead of the built-in MTP head. It drafts 7 tokens per step and ~5.1 get accepted. It is quantized to FP8 at load time (`"quantization":"fp8"`), which matches BF16 speed and frees ~48K tokens of KV. **Don't use the pre-quantized FP8 checkpoint**: at TP=4 it got 0 % acceptance.
4. `--async-scheduling`: about +4 % at 3 sessions.
5. **NVFP4 KV cache** (`--kv-cache-dtype nvfp4`): 933K tokens of context instead of 584K with fp8, at the same speed. The drafter keeps its own KV for every token too, so shrinking the KV matters more than shrinking the drafter's weights. A recall test (three facts hidden at 10/50/90 % of a 146K-token prompt) passed 3/3 on both fp8 and nvfp4.

**Things that didn't help:** P2P through NCCL alone, the CPU governor, `--max-num-batched-tokens 16384` (runs out of memory at startup), 8192 (+8 % prefill but −4 % at 8 sessions and less KV), MTP 6 or more (faster for one session, slower for 8).

## Hardware

- ASUS ROG Zenith Extreme Alpha (X399), Threadripper 1920X, 64 GB DDR4, 1000 W PSU
- 4× RTX 5060 Ti 16 GB (two directly in slots, two on PCIe 4.0 risers), all at Gen3 x8
- Ubuntu Server 24.04, booted in **UEFI** mode

## BIOS (manual)

- **UEFI only:** CSM off. Re-Size BAR needs it, and the RTX 50 cards hang at Q-code B2 with legacy option ROMs. If Ubuntu was installed in legacy mode, add an EFI partition and install `grub-efi-amd64-signed` + `shim-signed` before turning CSM off.
- **Above 4G Decoding** and **Re-Size BAR** on. Check from Linux: `lspci -vv` should show `BAR 1: current size: 16GB`.
- On the Zenith Extreme Alpha: PCIEX16_2 = **X8 Mode**, PCIEX16_4 = **X8 mode**. The default X4 mode reserves lanes for the onboard M.2.
- A dead CMOS battery resets all of this on power loss. Replace it and save an ASUS user profile.
- For the board's VRM fans (a known full-speed bug), see [vrm-fan-control](https://github.com/MaciejCwalina/vrm-fan-control).

## Setup

```sh
./setup.sh host     # IOMMU passthrough, nouveau blacklist        -> reboot
./setup.sh driver   # NVIDIA 615.78.08 + P2P-patched modules     -> reboot
./setup.sh check    # expect: BAR1 16384 MiB, iommu=pt, UEFI, P2P "OK" for all pairs
./setup.sh docker   # Docker + NVIDIA container toolkit
./setup.sh models   # ~25 GB: model + DFlash2 drafter
./setup.sh key      # API key -> ~/llm/vllm.env (mode 600, never printed)
./setup.sh start    # start vLLM on :8000 (first start ~5-8 min)
python3 bench.py 3 8
```

**Kernel updates:** the patched modules aren't DKMS, so `setup.sh driver` holds the kernel packages. To update the kernel, unhold it, upgrade, re-run `./setup.sh driver`, then reboot.

## VRAM overclock

Decode is limited by memory bandwidth, so a GDDR7 overclock helps. NVML allows offsets from −2000 to +6000 on the 5060 Ti (NVML units; +1000 ≈ +500 MHz real). Measured with vLLM running, greedy outputs compared against stock after every step:

| Offset | Memory clock | 1 session | 3 sessions | Code | Greedy output vs stock | Xid |
|---|---|---|---|---|---|---|
| 0 | 14,001 MHz | 252 | 554 | 258 | — | 0 |
| +3000 | 15,501 MHz | 263 | 574 | 273 | identical 6/6 | 0 |
| **+5000** | **16,501 MHz** | **267** | **613** | **281** | identical 6/6 | 0 |
| +6000 | 17,001 MHz | 276 | 569 | 284 | identical 6/6 | 0 |

+5000 is the default (`vram-oc/`): about +10 % at 3 sessions. `vram-oc-guard` enables persistence mode, applies the offset at boot, checks the kernel log for NVIDIA Xid errors every 5 s, and on the first one resets every GPU to stock. No voltage change; a reboot or `systemctl stop vram-oc-guard` also returns to stock.

## Monitoring

`./setup.sh monitoring` starts Prometheus, Grafana (:3000), node exporter and an NVIDIA GPU exporter (Docker, host network). The home dashboard shows the VRAM offset, Xid errors, the watchdog state, tok/s, running requests, drafter acceptance, KV cache use, per-card clock/temperature/power/utilization (by card name), VRM temperature and fan RPM. Node Exporter Full, NVIDIA GPU and the upstream vLLM dashboards are provisioned too.

Discord alerts (Grafana alerting, webhook in `monitoring/grafana.env`, never committed): Xid error, watchdog reset to stock, vLLM down 1 min, GPU > 80 °C for 2 min, VRM > 90 °C for 2 min, KV cache > 95 % for 5 min.

**Live streaming:** see the [stream-hub](https://github.com/MaciejCwalina/stream-hub) repo — a push-based metric hub (systemd, `127.0.0.1:9797`) plus the local Grafana plugin `home-llm-live`, which streams frames straight into panels with no polling. The "Home LLM live (streaming)" dashboard shows vLLM throughput/scheduler/KV/drafter, all four GPUs and the VRAM OC state in real time. Prometheus stays the system of record (history + alerts); the stream is the live glass.

## Runtime switches (`start-vllm.sh`)

| Variable | Effect |
|---|---|
| `KV_CACHE_DTYPE=fp8` | back to the fp8 KV cache (584K tokens) |
| `SPEC_CONFIG=mtp` | use the built-in MTP head instead of DFlash2 (183 / 438 / 745 tok/s, KV ~773K) |
| `MTP_TOKENS=5` | MTP draft length (5 is the best balance) |
| `VLLM_DOCKER_ENV="..."` | override the container environment; the default enables the FlashInfer all-reduce |
| `VLLM_EXTRA_ARGS="..."` | override the extra `vllm serve` flags (default `--async-scheduling`) |
