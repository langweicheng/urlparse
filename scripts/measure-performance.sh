#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PROBE_DIR=$(mktemp -d /tmp/urlparser-performance.XXXXXX)
cp Package.swift "$PROBE_DIR/"
cp -R Sources Tests "$PROBE_DIR/"
cp scripts/PerformanceProbe.swift "$PROBE_DIR/Sources/URLParser/"
python3 - "$PROBE_DIR/Sources/URLParser/main.swift" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text().replace('        NSApp.activate(ignoringOtherApps: true)', '        PerformanceProbe.start(self)')
p.write_text(s)
PY
swift build --package-path "$PROBE_DIR" -c release -Xswiftc -Osize -Xswiftc -DPERFORMANCE_PROBE
"$PROBE_DIR/.build/release/URLParser" | tee "$PROBE_DIR/results.txt"
printf 'Results: %s/results.txt\n' "$PROBE_DIR"
