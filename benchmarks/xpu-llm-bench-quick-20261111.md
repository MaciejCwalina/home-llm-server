# home-dflash2-k7-20261111T211903-c0825ea2

## Header

| field | value |
| --- | --- |
| spec / profile | home-dflash2-k7 / quick |
| status | completed |
| started (Europe/Warsaw) | 2026-11-11T22:19:03.066188+01:00 |
| container | vllm-bench 5e897f88400b |
| image tag / ID | None / sha256:d825baf9ce4b1b6bfc5ecc7b79880c7e6748c65a72d697ce3d47607aafa84c6e |
| build fingerprint | da6035b0f0be95ee6ff16b8e196149a9d98896019d083958ad86cdff15d61895 |
| boot started | 2026-11-11T21:16:02.074799417Z |
| attention (boot log) | unknown (requested auto) |
| graphs (boot log) | on=True mode=FULL_AND_PIECEWISE sizes=[] counts={'PIECEWISE': '19/19', 'FULL': '8/8'} |
| KV | nvfp4 — 932758 tokens |
| speculative | dflash k=7 (spec k=None) |
| max model len | 262144 |
| prompt seed | 20261111 |
| decode method | fixed-tokens-chunks-v2 |
| hold | {'skipped': 'no safety.hold_command configured; no bench-hold taken'} |

## Evidence (quoted log lines)

```
(Worker_TP2 pid=221) INFO 11-11 21:18:28 [model_runner.py:1163] Graph capturing finished in 13 secs, took 0.91 GiB
(Worker_TP3 pid=223) INFO 11-11 21:18:28 [model_runner.py:1163] Graph capturing finished in 13 secs, took 0.91 GiB
(Worker_TP0 pid=220) INFO 11-11 21:18:28 [model_runner.py:1163] Graph capturing finished in 13 secs, took 0.91 GiB
(Worker_TP1 pid=222) INFO 11-11 21:18:28 [model_runner.py:1163] Graph capturing finished in 13 secs, took 0.91 GiB
(EngineCore pid=150) INFO 11-11 21:18:29 [kv_cache_utils.py:1147] GPU KV cache size: 932,758 tokens, Maximum concurrency for 262,144 tokens per request: 3.56x
(Worker_TP3 pid=223) INFO 11-11 21:18:43 [model_runner.py:1163] Graph capturing finished in 12 secs, took 0.17 GiB
(Worker_TP0 pid=220) INFO 11-11 21:18:43 [model_runner.py:1163] Graph capturing finished in 12 secs, took 0.17 GiB
(Worker_TP1 pid=222) INFO 11-11 21:18:43 [model_runner.py:1163] Graph capturing finished in 12 secs, took 0.17 GiB
(Worker_TP2 pid=221) INFO 11-11 21:18:43 [model_runner.py:1163] Graph capturing finished in 12 secs, took 0.17 GiB
SpeculativeConfig(method='dflash', model='/models/qwen3.8-27b-dflash2', num_spec_tokens=7)
```

## Ladder

| rung_id | users | ctx_tokens | attention_path | steps_s_per_user | decode_tok_s_per_user | decode_tok_s_total | tokens_per_step | hit_rate | prefill_tok_s | ttft_ms | itl_p95_ms | kv_cache_usage_max_pct | mem_available_min_gib | quality | flags |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| code_edits:closed:1u:8192:S | 1 | 8202 | unknown | 45.57 | 333.04 | 333.04 | 7.308 | 0.901 | 1224.70 | 1116.1 | 23.2 | 0.000 | 40.384 | needle ok, code ok, greedy no_reference | K_UNDECLARED SHORT_WINDOW |
| code_edits:closed:1u:32768:S | 1 | 32647 | unknown | 46.73 | 369.94 | 369.94 | 7.917 | 0.988 | 2087.15 | 357.3 | 24.2 | 0.000 | 40.384 | needle ok, code ok, greedy no_reference | K_UNDECLARED SHORT_WINDOW |
| code_edits:closed:2u:8192:C | 2 | 8104/8181 | unknown | 24.45 | 165.91 | 331.83 | 6.786 | 0.827 | 2290.53 | 1688.0 | 166.6 | 11.939 | 40.384 | needle ok, greedy no_reference | K_UNDECLARED SHORT_WINDOW |
| code_edits:closed:4u:8192:C | 4 | 8163/8232/8141/8192 | unknown | 14.83 | 88.19 | 352.75 | 5.588 | 0.655 | 2303.30 | 3069.3 | 808.6 | 23.273 | 40.384 | needle ok, greedy no_reference | CONCURRENT_CLIENT K_UNDECLARED SHORT_WINDOW |
| code_edits:closed:8u:8192:C | 8 | 8167/8194/8187/8119/8121/8199/8150/8216 | unknown | 7.05 | 46.74 | 373.89 | 6.496 | 0.785 | 2283.85 | 4981.5 | 882.3 | 45.818 | 40.384 | needle ok, greedy no_reference | CONCURRENT_CLIENT K_UNDECLARED SHORT_WINDOW |
| long_form:closed:1u:8192:S | 1 | 8133 | unknown | 45.33 | 187.22 | 187.22 | 4.130 | 0.447 | 2286.05 | 1114.4 | 22.6 | 0.000 | 40.384 | needle ok, format ok, greedy no_reference | K_UNDECLARED |
| long_form:closed:1u:32768:S | 1 | 32720 | unknown | 45.07 | 237.89 | 237.89 | 5.278 | 0.611 | 2091.93 | 369.4 | 24.0 | 0.000 | 40.384 | needle ok, format ok, greedy no_reference | K_UNDECLARED SHORT_WINDOW |
| long_form:closed:2u:8192:C | 2 | 8158/8192 | unknown | 26.11 | 114.11 | 228.22 | 4.222 | 0.460 | 2295.92 | 1685.8 | 31.7 | 11.939 | 40.384 | needle ok, format ok, greedy no_reference | K_UNDECLARED |
| long_form:closed:4u:8192:C | 4 | 8158/8120/8140/8180 | unknown | 17.45 | 78.59 | 314.36 | 4.419 | 0.488 | 2284.82 | 2968.5 | 335.0 | 23.939 | 40.384 | needle ok, format ok, greedy no_reference | CONCURRENT_CLIENT K_UNDECLARED |
| long_form:closed:8u:8192:C | 8 | 8191/8058/8072/8138/8136/8128/8098/8096 | unknown | 7.00 | 33.01 | 264.05 | 4.606 | 0.515 | 2281.21 | 5067.8 | 879.8 | 45.818 | 40.384 | needle ok, format ok, greedy no_reference | CONCURRENT_CLIENT K_UNDECLARED SHORT_WINDOW |
| multi_turn_chat:closed:1u:8192:S | 1 | 8153 | unknown | 45.03 | 129.65 | 129.65 | 2.879 | 0.268 | 2289.30 | 1123.6 | 23.5 | 5.636 | 40.384 | needle ok, format ok, greedy no_reference | K_UNDECLARED |
| multi_turn_chat:closed:1u:32768:S | 1 | 32854 | unknown | 45.68 | 228.38 | 228.38 | 5.000 | 0.571 | 2091.57 | 429.8 | 23.7 | 0.000 | 40.384 | needle ok, format ok, greedy no_reference | K_UNDECLARED SHORT_WINDOW |
| multi_turn_chat:closed:2u:8192:C | 2 | 8152/8105 | unknown | 26.75 | 91.72 | 183.44 | 3.455 | 0.351 | 2281.98 | 1690.4 | 27.0 | 11.939 | 40.384 | needle ok, format ok, greedy no_reference | K_UNDECLARED |
| multi_turn_chat:closed:4u:8192:C | 4 | 8148/8111/8135/8166 | unknown | 18.40 | 66.18 | 264.74 | 3.519 | 0.360 | 2283.52 | 2971.0 | 309.6 | 23.273 | 40.384 | needle ok, format ok, greedy no_reference | CONCURRENT_CLIENT K_UNDECLARED |
| multi_turn_chat:closed:8u:8192:C | 8 | 8109/8179/8179/8118/8156/8187/8134/8102 | unknown | 7.68 | 27.04 | 216.32 | 3.486 | 0.355 | 2285.94 | 5074.6 | 881.1 | 45.818 | 40.384 | needle ok, format ok, greedy no_reference | CONCURRENT_CLIENT K_UNDECLARED |

## Flags

- `CONCURRENT_CLIENT`: More running/waiting requests than this runner's sessions (another client).
- `K_UNDECLARED`: Spec did not declare k; k was taken from draft_tokens/drafts.
- `SHORT_WINDOW`: Fewer verify steps per session than ladder.min_window_steps.

## Full rows

CSV with every column: `bench report <results.jsonl> --csv out.csv`.
