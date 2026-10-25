#!/bin/bash
# Report the ABI and CPU floor of every ELF in a wheel or a directory.
# Exits 1 when an object contains AVX, AVX-512, or a GLIBC/GLIBCXX version
# above the optional ceilings in $MAX_GLIBC and $MAX_GLIBCXX (for example
# 2.39 and 3.4.32).

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <wheel-or-directory>" >&2
  exit 2
fi

target="$1"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

case "$target" in
  *.whl|*.zip)
    unzip -q "$target" -d "$work/unpack"
    root="$work/unpack"
    ;;
  *)
    if [ -d "$target" ]; then
      root="$target"
    else
      mkdir -p "$work/one"
      cp -a "$target" "$work/one/$(basename "$target")"
      root="$work/one"
    fi
    ;;
esac

highest() {
  printf '%s\n' "$1" | sed '/^$/d' | sort -uV | tail -1
}

audit_one() {
  local elf="$1"
  local glibc glibcxx cxxabi ymm zmm dyn text
  dyn="$(
    objdump -T "$elf" 2>/dev/null || true
    readelf -sW "$elf" 2>/dev/null || true
  )"
  text="$(objdump -d "$elf" 2>/dev/null || true)"
  glibc="$(highest "$(printf '%s\n' "$dyn" | sed -n 's/.*GLIBC_\([0-9.]*\).*/\1/p')")"
  glibcxx="$(highest "$(printf '%s\n' "$dyn" | sed -n 's/.*GLIBCXX_\([0-9.]*\).*/\1/p')")"
  cxxabi="$(highest "$(printf '%s\n' "$dyn" | sed -n 's/.*CXXABI_\([0-9.]*\).*/\1/p')")"
  ymm="$(printf '%s\n' "$text" | grep -c -E '%ymm|vinserti|vinsertf|vpbroadcast|vpadd' || true)"
  zmm="$(printf '%s\n' "$text" | grep -c -E '%zmm|vpternlog' || true)"
  popcnt="$(printf '%s\n' "$text" | grep -c popcnt || true)"
  echo "glibc=${glibc:-none} glibcxx=${glibcxx:-none} cxxabi=${cxxabi:-none} ymm=${ymm} zmm=${zmm} popcnt=${popcnt}"
  if [ "$ymm" != "0" ] || [ "$zmm" != "0" ] || [ "$popcnt" != "0" ]; then
    echo "CPU floor is above x86-64 baseline" >&2
    fail=1
  fi
  if [ -n "${MAX_GLIBC:-}" ] && [ -n "$glibc" ]; then
    newest="$(printf '%s\n%s\n' "$glibc" "$MAX_GLIBC" | sort -V | tail -1)"
    if [ "$newest" != "$MAX_GLIBC" ]; then
      echo "GLIBC_${glibc} exceeds GLIBC_${MAX_GLIBC}" >&2
      fail=1
    fi
  fi
  if [ -n "${MAX_GLIBCXX:-}" ] && [ -n "$glibcxx" ]; then
    newest="$(printf '%s\n%s\n' "$glibcxx" "$MAX_GLIBCXX" | sort -V | tail -1)"
    if [ "$newest" != "$MAX_GLIBCXX" ]; then
      echo "GLIBCXX_${glibcxx} exceeds GLIBCXX_${MAX_GLIBCXX}" >&2
      fail=1
    fi
  fi
}

fail=0
while IFS= read -r -d '' elf; do
  echo "== $elf"
  case "$elf" in
    *.a)
      members="$(mktemp -d)"
      (cd "$members" && ar x "$elf")
      for obj in "$members"/*.o; do
        echo "-- $(basename "$obj")"
        audit_one "$obj"
      done
      rm -rf "$members"
      ;;
    *)
      audit_one "$elf"
      ;;
  esac
done < <(find "$root" -type f \( -name '*.so' -o -name '*.a' \) -print0)

exit "$fail"
