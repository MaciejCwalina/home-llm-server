#!/usr/bin/env python3
"""Throughput benchmark against a running vLLM server: single session, N sessions at once, then prompt reading.

usage: bench.py [concurrency ...]      (default: 8 16)
Defaults to the local server (http://localhost:8000, key from ~/llm/vllm.env); nothing secret is printed.
Set BENCH_URL and BENCH_KEY_FILE to benchmark another server (BENCH_KEY_FILE may hold the bare key or VLLM_API_KEY=...).
"""
import concurrent.futures
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

base_url = os.environ.get("BENCH_URL", "http://localhost:8000")
key_file = Path(os.environ.get("BENCH_KEY_FILE", "~/llm/vllm.env")).expanduser()
api_key = key_file.read_text().strip().removeprefix("VLLM_API_KEY=")
headers = {"Authorization": "Bearer " + api_key, "Content-Type": "application/json"}
model_name = json.load(urllib.request.urlopen(urllib.request.Request(base_url + "/v1/models", headers=headers), timeout=30))["data"][0]["id"]
prompt = ("Write a Python class implementing an LRU cache with get, put, delete and __len__, using OrderedDict, "
          "with docstrings and type hints. Then write unittest tests for it.")


def complete(content, max_tokens):
    body = {"model": model_name, "max_tokens": max_tokens, "temperature": 0.6,
            "messages": [{"role": "user", "content": content}], "chat_template_kwargs": {"enable_thinking": False}}
    request = urllib.request.Request(base_url + "/v1/chat/completions", json.dumps(body).encode(), headers)
    started = time.time()
    response = json.load(urllib.request.urlopen(request, timeout=1800))
    return response, time.time() - started


def generation(index):
    response, seconds = complete(prompt + f" Variant {index}.", 800)
    return response["usage"]["completion_tokens"], seconds


generation(-1)  # warm-up
single_rates = [tokens / seconds for tokens, seconds in (generation(index) for index in range(3))]
print(f"single session: {sum(single_rates) / len(single_rates):.1f} tok/s", flush=True)

for concurrency in [int(value) for value in sys.argv[1:]] or [8, 16]:
    with concurrent.futures.ThreadPoolExecutor(concurrency) as pool:  # warm-up: compile kernels for this batch size
        list(pool.map(generation, range(50, 50 + concurrency)))
    started = time.time()
    with concurrent.futures.ThreadPoolExecutor(concurrency) as pool:
        results = list(pool.map(generation, range(100, 100 + concurrency)))
    elapsed = time.time() - started
    total = sum(tokens for tokens, _ in results)
    per_session = sum(tokens / seconds for tokens, seconds in results) / len(results)
    print(f"{concurrency} at once: {total / elapsed:.1f} tok/s total, {per_session:.1f} tok/s per session", flush=True)

source = Path(__file__).resolve()
filler = (source.read_text() * 200)[:110000]
response, seconds = complete(filler + "\n\nIn one sentence, what is this text?", 60)
print(f"prompt reading: {response['usage']['prompt_tokens']} tokens in {seconds:.1f}s "
      f"(~{response['usage']['prompt_tokens'] / seconds:.0f} tok/s incl. 60 output tokens)", flush=True)
