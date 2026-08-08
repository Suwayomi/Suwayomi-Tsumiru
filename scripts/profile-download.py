#!/usr/bin/env python3
"""Capture a Dart CPU profile from a running profile-mode build and report where
the time actually goes.

    scripts/profile-download.py <vm-service-uri> [seconds]

CPU percentages can't tell an expensive write path apart from work being redone;
only a profile names the function. Start this, run the download, read the list.
"""
import json
import sys
import time
import urllib.parse
import urllib.request
from collections import Counter


def rpc(uri, method, **params):
    url = uri + method
    if params:
        url += "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=30) as r:
        body = json.load(r)
    if "error" in body:
        raise SystemExit(f"{method} failed: {body['error']}")
    return body["result"]


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    uri = sys.argv[1]
    if not uri.endswith("/"):
        uri += "/"
    duration = int(sys.argv[2]) if len(sys.argv) > 2 else 60

    rpc(uri, "setFlag", name="profiler", value="true")
    vm = rpc(uri, "getVM")
    isolates = vm["isolates"]
    iso = next((i for i in isolates if "main" in i["name"]), isolates[0])["id"]

    origin = int(rpc(uri, "getVMTimelineMicros")["timestamp"])
    print(f"Profiling isolate {iso} for {duration}s — run the download now.", flush=True)
    for left in range(duration, 0, -5):
        print(f"  {left}s left", end="\r", flush=True)
        time.sleep(min(5, left))
    print(" " * 24, end="\r")

    extent = int(rpc(uri, "getVMTimelineMicros")["timestamp"]) - origin
    samples = rpc(
        uri, "getCpuSamples",
        isolateId=iso, timeOriginMicros=origin, timeExtentMicros=extent,
    )

    funcs = samples.get("functions", [])
    names = []
    for entry in funcs:
        f = entry.get("function") or {}
        name = f.get("name", "?")
        owner = f.get("owner") or {}
        cls = owner.get("name")
        # Library owners carry a uri; class owners carry a name worth prefixing.
        if cls and owner.get("type") in ("@Class", "Class") and cls != name:
            name = f"{cls}.{name}"
        names.append(name)

    self_time, total_time = Counter(), Counter()
    for s in samples.get("samples", []):
        stack = s.get("stack", [])
        if not stack:
            continue
        if stack[0] < len(names):
            self_time[names[stack[0]]] += 1
        for idx in set(stack):
            if idx < len(names):
                total_time[names[idx]] += 1

    n = samples.get("sampleCount", 0)
    print(f"\n{n} samples over {extent / 1e6:.1f}s "
          f"(period {samples.get('samplePeriod')}us)\n")
    if not n:
        print("No samples. Was anything actually running?")
        return

    print("=== SELF TIME — where cycles are actually spent ===")
    for name, c in self_time.most_common(25):
        print(f"  {100 * c / n:6.2f}%  {c:6d}  {name}")

    print("\n=== TOTAL TIME — on the stack, incl. callees ===")
    for name, c in total_time.most_common(25):
        print(f"  {100 * c / n:6.2f}%  {c:6d}  {name}")


if __name__ == "__main__":
    main()
