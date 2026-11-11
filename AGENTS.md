# AGENTS.md — home-llm-server

Context for agents working on this project. The project is a source repo; the running system lives on the remote server.

## The server

- SSH: `ssh llm` → `pl-plo-ai-server-01` (Ubuntu Server 24.04, UEFI).
- Hardware: Threadripper 1920X (X399), 4× RTX 5060 Ti 16 GB at Gen3 x8, P2P between all cards (aikitoria-patched NVIDIA 615.78.08 modules, not DKMS).
- Workload: vLLM serving **Swift-Qwen3.8-27B NVFP4** (TP=4) on `:8000`, DFlash2 speculative decoding, NVFP4 KV cache. Details and benchmarks: `README.md`.
- Server-side layout: `~/llm/` (models, cache, scripts, `monitoring/`), `/home/maciej/p2p/` (kernel module build), `/home/maciej/it87/` (IT87 sensor driver).

## Monitoring / observability (investigated 2026-11-11)

Stack: docker-compose in `monitoring/` (mirrored at `~/llm/monitoring/` on the server). All containers use **host networking**.

| Service | Port | Notes |
|---|---|---|
| Prometheus | 9090 | 60d retention, **1s scrape** (streaming-grade; alert eval stays at 5s) |
| Grafana | 3000 | admin password from `grafana.env` (mode 600); signups off; home dashboard = `home-llm-overview.json`; **all dashboards auto-refresh 1s** |
| node-exporter | 9100 | `pid: host`; **textfile collector** reads `/var/lib/node_exporter/textfile/` |
| nvidia_gpu_exporter | 9835 | `utkuozdemir/nvidia_gpu_exporter`, all GPUs |

Prometheus jobs (`prometheus.yml`): `vllm` (localhost:8000), `node` (9100), `nvidia-gpu` (9835), `prometheus` (9090).

### Dashboards (provisioned from `monitoring/grafana/dashboards/`)

Folder "Home LLM server":
- `home-llm-overview.json` — custom: VRAM OC stats, total tok/s, drafter acceptance, KV usage, per-card clock/temp/power/util, CPU VRM + Tdie temps, fan RPM, CPU/RAM.
- `vllm.json` — upstream vLLM dashboard (TTFT/ITL/TPOT/E2E, scheduler state, length heatmaps, finish reasons).
- `nvidia-gpu.json`, `node-exporter-full.json` — stock.

### Alerts (Grafana unified alerting, `provisioning/alerting/alerts.yml`)

Discord contact point via `DISCORD_WEBHOOK_URL` in `grafana.env` (mode 600, never committed). Grouped by alertname, 30s wait, 4h repeat, 30s evaluation:

| Rule | Severity | Condition |
|---|---|---|
| xid-error | critical | `vram_oc_xid_errors_total > 0` |
| watchdog-tripped | critical | `vram_oc_tripped > 0` |
| vllm-down | critical | `up{job="vllm"} < 1` for 1m (noData = alerting) |
| gpu-hot | warning | GPU temp > 80 °C for 2m |
| vrm-hot | warning | CPU VRM > 90 °C for 2m |
| kv-cache-full | info | max KV usage > 0.95 for 5m |

### Custom metrics pipeline (VRAM overclock watchdog)

`vram-oc-guard.service` (systemd, enabled; script at `/usr/local/bin/vram-oc-guard`, source in `vram-oc/` here):
- Applies GDDR7 memclk offset from `/etc/default/vram-oc` (`OFFSET_MHZ=5000` → 16.5 GHz) to all 4 GPUs via NVML; persistence mode on.
- Every second counts `NVRM: Xid` lines in dmesg; on a new Xid it resets all GPUs to stock and stays there until the service is restarted by hand.
- Writes `/var/lib/node_exporter/textfile/vram_oc.prom`: `vram_oc_offset_mhz` (gauge), `vram_oc_xid_errors_total` (counter), `vram_oc_tripped` (gauge).
- `ExecStopPost` resets the offset as a fallback; `systemctl stop vram-oc-guard` also returns to stock.
- `/var/lib/node_exporter/textfile/gpu_cards.prom` provides `gpu_card_info{uuid,card}` labels — friendly card names used in legends/alerts via `* on(uuid) group_left(card) gpu_card_info`:
  - GPU0 ASUS Dual, GPU1 Gigabyte Eagle, GPU2 Gainward Python III, GPU3 Zotac Twin Edge.

### Conventions & gotchas

- Secrets are mode-600 env files, deliberately not in git: `monitoring/grafana.env` (Grafana password, Discord webhook), `~/llm/vllm.env` (vLLM API key, passed as `VLLM_API_KEY`, never on the command line).
- hwmon joins use `node_hwmon_sensor_label` to map raw chip IDs to labels (`CPU VRM Temperature`, `Tdie`); Tdie chips match `chip=~".*00:18_3|.*00:19_3"`.
- Sub-second latency is achieved by 1s scrape + 1s dashboard refresh (Grafana "Live" WebSocket streaming only works with plugin datasources, not the standard Prometheus one — polling at 1s is the practical equivalent).
- Kernel updates: patched GPU modules aren't DKMS — `setup.sh driver` holds kernel packages; unhold, upgrade, re-run `setup.sh driver`, reboot.
- Dead CMOS battery resets BIOS (Re-Size BAR, UEFI) — known failure mode.
- Useful live checks: `curl -s localhost:9090/api/v1/query?query=up`, `curl -s localhost:8000/metrics`, `journalctl -u vram-oc-guard`, `cat /var/lib/node_exporter/textfile/*.prom`.
- `bench.py N M` runs the benchmark (N single-session, M concurrent); `oc-soak.sh` runs the 30-min soak + greedy-parity check against stock.

## Repo layout

- `setup.sh` — idempotent setup commands (`host`, `driver`, `check`, `docker`, `models`, `key`, `start`, `monitoring`).
- `start-vllm.sh` — vLLM launch script; runtime switches documented in README.
- `monitoring/` — compose file, prometheus.yml, dashboards, provisioning (datasources, dashboards, alerting).
- `vram-oc/` — watchdog script source.
- `bench.py` — benchmark client.
