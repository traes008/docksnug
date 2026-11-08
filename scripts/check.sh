#!/bin/sh
# Compiles and runs the logic checks. Needs only the command-line Swift tools.
set -e
cd "$(dirname "$0")/.."
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
swiftc -swift-version 5 DockFit/DockGeometry.swift Tests/main.swift -o "$out/checks"
"$out/checks"
