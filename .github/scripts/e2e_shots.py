"""Puts the E2E's player screenshots back together.

The test prints each PNG as base64 chunks ("E2E-SHOT name i/n data"),
since the app and its files are gone after the run.
Usage: e2e_shots.py LOG OUTDIR
"""
import base64, collections, os, re, sys

log, out = sys.argv[1], sys.argv[2]
parts = collections.defaultdict(dict)
if os.path.exists(log):
    for line in open(log, errors='replace'):
        m = re.search(r'E2E-SHOT (\S+) (\d+)/(\d+) (\S+)', line)
        if m:
            parts[m[1]][int(m[2])] = (int(m[3]), m[4])
os.makedirs(out, exist_ok=True)
for name, chunks in parts.items():
    total = next(iter(chunks.values()))[0]
    if len(chunks) == total:
        data = ''.join(chunks[i][1] for i in range(1, total + 1))
        with open(f'{out}/{name}.png', 'wb') as f:
            f.write(base64.b64decode(data))
print('screenshots:', sorted(os.listdir(out)))
