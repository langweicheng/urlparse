#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Isolated build: the shipped app never contains the benchmark driver.
PROBE_DIR=$(mktemp -d /tmp/urlparser-memory.XXXXXX)
cp Package.swift "$PROBE_DIR/"
cp -R Sources Tests "$PROBE_DIR/"
cp scripts/MemoryProbe.swift "$PROBE_DIR/Sources/URLParser/"
python3 - "$PROBE_DIR/Sources/URLParser/main.swift" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text().replace('        NSApp.activate(ignoringOtherApps: true)', '        NSApp.activate(ignoringOtherApps: true)\n        MemoryProbe.start(self)')
path.write_text(text)
PY
swift build --package-path "$PROBE_DIR" -c release -Xswiftc -DMEMORY_PROBE
"$PROBE_DIR/.build/release/URLParser" | tee "$PROBE_DIR/results.txt"
printf 'Results: %s/results.txt\n' "$PROBE_DIR"
