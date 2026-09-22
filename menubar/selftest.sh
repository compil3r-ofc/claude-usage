#!/bin/bash
# Compiles UsageCore.swift against selftest.swift and runs the checks.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cp selftest.swift "$T/main.swift"
cp UsageCore.swift "$T/"
swiftc -swift-version 5 -framework AppKit -o "$T/run" "$T/UsageCore.swift" "$T/main.swift"
"$T/run"
