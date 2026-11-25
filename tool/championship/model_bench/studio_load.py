#!/usr/bin/env python3
"""Load a model in Unsloth Studio with an explicit context window.
usage: studio_load.py <model id> [context=32768]   (prints the loaded context)"""
import json, os, sys, time, urllib.request
p = json.load(open(os.path.expanduser("~/.pi/agent/models.json")))["providers"]["studio"]
base = p["baseUrl"].rstrip("/"); h = {"Authorization": "Bearer " + p["apiKey"], "Content-Type": "application/json"}
model, ctx = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 32768
def call(path, body=None):
    r = urllib.request.Request(base + path, data=json.dumps(body).encode() if body else None, headers=h)
    return json.load(urllib.request.urlopen(r, timeout=900))
# Ollama-sourced models load by Studio's reference id, not by their /v1 id.
root = base.rsplit("/v1", 1)[0]
local = json.load(urllib.request.urlopen(urllib.request.Request(root + "/api/models/local", headers=h), timeout=30))["models"]
path = next((x["id"] for x in local if x.get("model_id") == model), model)
try:
    out = call("/load", {"model_path": path, "max_seq_length": ctx, "force_cancel_active": True})
except urllib.error.HTTPError as e:
    sys.exit(f"load failed {e.code}: {e.read()[:300]}")
for _ in range(180):
    m = [x for x in call("/models")["data"] if x["id"] == model]
    if m and m[0].get("loaded"):
        print(m[0].get("context_length")); sys.exit(0 if (m[0].get("context_length") or 0) >= ctx else 1)
    time.sleep(5)
sys.exit("not loaded after 15 min")
