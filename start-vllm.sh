#!/usr/bin/env bash
# Start the local LLM server: Swift-Qwen3.8-27B NVFP4 on all 4 RTX 5060 Ti (tensor parallel).
# The API key lives in ~/llm/vllm.env (0600) and is passed as VLLM_API_KEY, never on the command line.
#
# Knobs (environment variables):
#   MTP_TOKENS=5                  speculative tokens for the built-in MTP head
#   SPEC_CONFIG='{...}'           replace the whole --speculative-config (e.g. a DFlash2 drafter)
#   VLLM_EXTRA_ARGS="..."         extra vllm serve flags (default: --async-scheduling)
#   VLLM_DOCKER_ENV="-e A=1 ..."  extra container environment (e.g. all-reduce switches)
#   KV_CACHE_DTYPE=nvfp4          KV cache format (nvfp4: 933K tokens, same speed and recall as fp8: 584K)
#   FORCE_CUSTOM_ALL_REDUCE=1     mount the patched custom_all_reduce.py (tested: slower, kept for reference)
set -euo pipefail
# Default drafter: DFlash2, quantized to FP8 at load (same speed as BF16, KV 584K vs 536K). The pre-quantized FP8 checkpoint gives 0% acceptance at TP=4.
# Set SPEC_CONFIG=mtp to use the built-in MTP head instead (MTP_TOKENS=5 is its best setting).
mtp_spec='{"method":"mtp","num_speculative_tokens":'"${MTP_TOKENS:-5}"'}'
dflash_spec='{"method":"dflash","model":"/models/qwen3.8-27b-dflash2","num_speculative_tokens":7,"quantization":"fp8"}'
case "${SPEC_CONFIG:-dflash}" in mtp) default_spec=$mtp_spec ;; *) default_spec=$dflash_spec ;; esac
case "${SPEC_CONFIG:-dflash}" in mtp|dflash) spec_config=$default_spec ;; *) spec_config=$SPEC_CONFIG ;; esac
custom_all_reduce_target=/usr/local/lib/python3.12/dist-packages/vllm/distributed/device_communicators/custom_all_reduce.py

docker rm -f vllm >/dev/null 2>&1 || true
# shellcheck disable=SC2086  # VLLM_DOCKER_ENV and VLLM_EXTRA_ARGS are intentionally word-split
docker run -d --name vllm --restart unless-stopped \
  --gpus all --ipc=host \
  -p 8000:8000 \
  -v "$HOME/llm/models:/models:ro" \
  -v "$HOME/llm/cache:/root/.cache" \
  --env-file "$HOME/llm/vllm.env" \
  ${FORCE_CUSTOM_ALL_REDUCE:+-v "$HOME/llm/patches/custom_all_reduce.py:$custom_all_reduce_target:ro"} \
  ${VLLM_DOCKER_ENV:--e VLLM_ALLREDUCE_USE_FLASHINFER_PCIE_IPC=1 -e NCCL_P2P_LEVEL=SYS} \
  vllm/vllm-openai:latest \
  --model /models/swift-qwen3.8-27b-nvfp4 \
  --served-model-name swift-qwen3.8-27b-uncensored \
  --tensor-parallel-size 4 \
  --max-model-len 262144 \
  --kv-cache-dtype "${KV_CACHE_DTYPE:-nvfp4}" \
  --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION:-0.94}" \
  --max-num-seqs 8 \
  --reasoning-parser qwen3 \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_coder \
  --speculative-config "$spec_config" \
  ${VLLM_EXTRA_ARGS:---async-scheduling}
