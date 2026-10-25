#!/bin/bash
# Report the ABI and CPU floor of the native objects this project ships:
# the extension modules, the bundled libFuzzer archive, and the merged
# sanitizer objects. A wheel that does not contain that set fails.
# An empty directory fails. A missing objdump, readelf, or ar fails.
#
# Exits 1 when an object contains AVX, AVX-512, or POPCNT, or a GLIBC or
# GLIBCXX version above the optional ceilings in $MAX_GLIBC and $MAX_GLIBCXX.

set -euo pipefail

if [ "${1:-}" = "--self-check" ]; then
  empty="$(mktemp -d)"
  set +e
  "$0" "$empty" >/dev/null 2>"$empty/err"
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    echo "self-check: empty input was accepted" >&2
    rm -rf "$empty"
    exit 1
  fi
  if ! grep -q "no native objects" "$empty/err"; then
    echo "self-check: empty input failed for another reason" >&2
    cat "$empty/err" >&2
    rm -rf "$empty"
    exit 1
  fi
  rm -rf "$empty"
  echo "self-check: empty input rejected"
  exit 0
fi

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <wheel-or-archive> | --self-check" >&2
  exit 2
fi

for tool in objdump readelf ar; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "required tool is missing: $tool" >&2
    exit 1
  fi
done

target="$1"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

case "$target" in
  *.whl|*.zip)
    if ! command -v unzip >/dev/null 2>&1; then
      echo "required tool is missing: unzip" >&2
      exit 1
    fi
    unzip -q "$target" -d "$work/unpack"
    root="$work/unpack"
    kind=wheel
    ;;
  *.a)
    mkdir -p "$work/one"
    cp -a "$target" "$work/one/$(basename "$target")"
    root="$work/one"
    kind=archive
    ;;
  *)
    if [ -d "$target" ]; then
      root="$target"
      kind=directory
    else
      echo "expected a wheel or a static archive, got $target" >&2
      exit 2
    fi
    ;;
esac

highest() {
  printf '%s\n' "$1" | sed '/^$/d' | sort -uV | tail -1
}

audit_one() {
  local elf="$1"
  local glibc glibcxx cxxabi ymm zmm popcnt dyn text
  if ! text="$(objdump -d "$elf" 2>/dev/null)"; then
    echo "objdump -d failed: $elf" >&2
    exit 1
  fi
  if ! dyn="$(readelf -sW "$elf" 2>/dev/null)"; then
    echo "readelf -sW failed: $elf" >&2
    exit 1
  fi
  # A shared object has a dynamic symbol table. A relocatable member does not.
  if [[ "$elf" == *.so ]]; then
    local dynamic
    if ! dynamic="$(objdump -T "$elf" 2>/dev/null)"; then
      echo "objdump -T failed: $elf" >&2
      exit 1
    fi
    dyn="${dyn}"$'\n'"${dynamic}"
  fi
  glibc="$(highest "$(printf '%s\n' "$dyn" | sed -n 's/.*GLIBC_\([0-9.]*\).*/\1/p')")"
  glibcxx="$(highest "$(printf '%s\n' "$dyn" | sed -n 's/.*GLIBCXX_\([0-9.]*\).*/\1/p')")"
  cxxabi="$(highest "$(printf '%s\n' "$dyn" | sed -n 's/.*CXXABI_\([0-9.]*\).*/\1/p')")"
  ymm="$(printf '%s\n' "$text" | grep -c -E '%ymm|vinserti|vinsertf|vpbroadcast|vpadd' || true)"
  zmm="$(printf '%s\n' "$text" | grep -c -E '%zmm|vpternlog' || true)"
  popcnt="$(printf '%s\n' "$text" | grep -c popcnt || true)"
  echo "glibc=${glibc:-none} glibcxx=${glibcxx:-none} cxxabi=${cxxabi:-none} ymm=${ymm} zmm=${zmm} popcnt=${popcnt}"
  if [ "$ymm" != "0" ] || [ "$zmm" != "0" ] || [ "$popcnt" != "0" ]; then
    echo "CPU floor is above x86-64 baseline: $elf" >&2
    fail=1
  fi
  if [ -n "${MAX_GLIBC:-}" ] && [ -n "$glibc" ]; then
    newest="$(printf '%s\n%s\n' "$glibc" "$MAX_GLIBC" | sort -V | tail -1)"
    if [ "$newest" != "$MAX_GLIBC" ]; then
      echo "GLIBC_${glibc} exceeds GLIBC_${MAX_GLIBC}: $elf" >&2
      fail=1
    fi
  fi
  if [ -n "${MAX_GLIBCXX:-}" ] && [ -n "$glibcxx" ]; then
    newest="$(printf '%s\n%s\n' "$glibcxx" "$MAX_GLIBCXX" | sort -V | tail -1)"
    if [ "$newest" != "$MAX_GLIBCXX" ]; then
      echo "GLIBCXX_${glibcxx} exceeds GLIBCXX_${MAX_GLIBCXX}: $elf" >&2
      fail=1
    fi
  fi
}

fail=0
audited=0
shopt -s nullglob
while IFS= read -r -d '' elf; do
  echo "== $elf"
  case "$elf" in
    *.a)
      members="$(mktemp -d)"
      (cd "$members" && ar x "$elf")
      objects=("$members"/*.o)
      if [ "${#objects[@]}" -eq 0 ]; then
        echo "archive has no objects: $elf" >&2
        exit 1
      fi
      for obj in "${objects[@]}"; do
        echo "-- $(basename "$obj")"
        audit_one "$obj"
        audited=$((audited + 1))
      done
      rm -rf "$members"
      ;;
    *.so)
      audit_one "$elf"
      audited=$((audited + 1))
      ;;
  esac
done < <(find "$root" -type f \( -name '*.so' -o -name '*.a' \) -print0)

if [ "$audited" -eq 0 ]; then
  echo "no native objects" >&2
  exit 1
fi

if [ "$kind" = "wheel" ]; then
  missing=0
  for name in \
    asan_with_fuzzer.so \
    ubsan_with_fuzzer.so \
    ubsan_cxx_with_fuzzer.so \
    libclang_rt.fuzzer_no_main-x86_64.a
  do
    if ! find "$root" -name "$name" | grep -q .; then
      echo "wheel is missing $name" >&2
      missing=1
    fi
  done
  for name in \
    core_with_libfuzzer \
    core_without_libfuzzer \
    native \
    custom_crossover \
    custom_mutator \
    mock_libfuzzer
  do
    if ! find "$root" -name "${name}*.so" | grep -q .; then
      echo "wheel is missing ${name} module" >&2
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    exit 1
  fi
fi

exit "$fail"
