#!/usr/bin/env python3
"""Build dist/Extract_Consolidate_ZIPs.scpt (AppleScript source text).

The shell engine (src/worker.sh) is embedded into the AppleScript wrapper
(src/wrapper.applescript.tpl) as escaped string chunks, so the final script is a
single self-contained file.  Run:  python3 build/build.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHUNK = 70  # lines per generated AppleScript handler (keeps handlers small)

def esc(line: str) -> str:
    return line.replace("\\", "\\\\").replace('"', '\\"')

def main() -> None:
    lines = (ROOT / "src" / "worker.sh").read_text(encoding="utf-8").split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    chunks = [lines[i:i + CHUNK] for i in range(0, len(lines), CHUNK)]
    calls, defs = [], []
    for n, chunk in enumerate(chunks, 1):
        calls.append(f"\tset w to w & my workerPart{n}()")
        body = [f"on workerPart{n}()", '\tset t to ""']
        body += [f'\tset t to t & "{esc(l)}" & linefeed' for l in chunk]
        body += ["\treturn t", f"end workerPart{n}", ""]
        defs.append("\n".join(body))
    tpl = (ROOT / "src" / "wrapper.applescript.tpl").read_text(encoding="utf-8")
    out = tpl.replace("@@CALLS@@", "\n".join(calls)).replace("@@CHUNKS@@", "\n".join(defs))
    dest = ROOT / "dist" / "Extract_Consolidate_ZIPs.scpt"
    dest.write_text(out, encoding="utf-8")
    print(f"Built {dest.relative_to(ROOT)}  ({len(chunks)} worker chunks, {len(out)} bytes)")

if __name__ == "__main__":
    main()
