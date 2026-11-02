#!/usr/bin/env bash
# Runs XCTests for Foundation-only sources on Linux (Docker image swift:6.1), without Xcode:
#   scripts/test-pure-swift.sh <test file> <source files…>
# The sources become a throw-away module "BrewLog" (Swift 5 mode), so tests keep their `@testable import BrewLog`.
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: $0 <test file> <source files…>" >&2
  exit 2
fi
test_file=$1
shift

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/Sources/BrewLog" "$tmp/Tests/BrewLogTests"
cp "$@" "$tmp/Sources/BrewLog/"
cp "$test_file" "$tmp/Tests/BrewLogTests/"
cat > "$tmp/Package.swift" <<'SWIFT'
// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "BrewLog", targets: [
    .target(name: "BrewLog", swiftSettings: [.unsafeFlags(["-swift-version", "5"])]),
    .testTarget(name: "BrewLogTests", dependencies: ["BrewLog"]),
])
SWIFT
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/pkg -v "$tmp":/pkg -w /pkg swift:6.1 swift test
