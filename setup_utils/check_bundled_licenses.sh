#!/bin/bash
# Confirm the sdist and wheel carry the pinned compiler-rt license and
# the notice, byte for byte.

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <sdist.tar.gz> <wheel>" >&2
  exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
sdist="$1"
wheel="$2"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

tar -xzf "$sdist" -C "$work"
src="$(echo "$work"/*)"
cmp -s "$root/compiler-rt/LICENSE.TXT" "$src/compiler-rt/LICENSE.TXT"
cmp -s "$root/NOTICE" "$src/NOTICE"

unzip -q "$wheel" -d "$work/wheel"
lic="$(echo "$work"/wheel/*.dist-info/licenses)"
cmp -s "$root/compiler-rt/LICENSE.TXT" "$lic/compiler-rt/LICENSE.TXT"
cmp -s "$root/NOTICE" "$lic/NOTICE"
echo "bundled license bytes match"
