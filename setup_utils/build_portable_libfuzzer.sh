#!/bin/bash
# Build libclang_rt.fuzzer_no_main for the x86-64 baseline.
#
# The archive Clang ships is often compiled for the packager's CPU. Linking
# that archive into the wheel makes a module that dies with SIGILL on any
# older runner. This script compiles the pinned compiler-rt fuzzer sources
# with an explicit baseline instead.
#
# Usage: build_portable_libfuzzer.sh <llvm-project-root> <output.a>

set -euo pipefail

if [ "$(uname -m)" != "x86_64" ]; then
  echo "the baseline libFuzzer archive is Linux x86_64 only (got $(uname -m))" >&2
  exit 1
fi

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <llvm-project-root> <output.a>" >&2
  exit 2
fi

llvm_root="$1"
output="$2"
fuzzer_dir="${llvm_root}/compiler-rt/lib/fuzzer"
include_dir="${llvm_root}/compiler-rt/include"

if [ ! -f "${fuzzer_dir}/FuzzerDriver.cpp" ]; then
  echo "no FuzzerDriver.cpp under ${fuzzer_dir}" >&2
  exit 1
fi
if [ ! -f "${include_dir}/sanitizer/lsan_interface.h" ]; then
  echo "no compiler-rt sanitizer headers under ${include_dir}" >&2
  exit 1
fi

cxx="${CXX:-clang++}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Upstream marks the compare path target("popcnt") and calls that body
# directly. There is no second version for CPUs without POPCNT, so the
# attribute would raise the wheel above the x86-64 baseline. Drop it.
# Popcountll then lowers to integer shifts at -march=x86-64.
cp -a "$fuzzer_dir" "$work/fuzzer"
sed -i 's/__attribute__((target("popcnt")))//' "$work/fuzzer/FuzzerPlatform.h"
if grep -q 'target("popcnt")' "$work/fuzzer/FuzzerPlatform.h"; then
  echo "failed to remove the popcnt target attribute" >&2
  exit 1
fi
fuzzer_dir="$work/fuzzer"

# Baseline only. -march=x86-64 is SSE2. -mtune=generic must not raise it.
flags=(
  -march=x86-64
  -mtune=generic
  -fPIC
  -fno-omit-frame-pointer
  -O2
  -std=c++17
  -fno-sanitize=all
  -fsanitize-coverage=0
  -g0
  -Wall
  -Wno-unused-parameter
  -I"${fuzzer_dir}"
  -I"${include_dir}"
)

shopt -s nullglob
sources=("${fuzzer_dir}"/*.cpp)
if [ "${#sources[@]}" -eq 0 ]; then
  echo "no fuzzer sources in ${fuzzer_dir}" >&2
  exit 1
fi

objects=()
for src in "${sources[@]}"; do
  base="$(basename "$src")"
  case "$base" in
    FuzzerMain.cpp|FuzzerInterceptors.cpp)
      continue
      ;;
  esac
  obj="${work}/${base%.cpp}.o"
  "$cxx" "${flags[@]}" -c "$src" -o "$obj"
  objects+=("$obj")
done

if [ "${#objects[@]}" -eq 0 ]; then
  echo "compiled no fuzzer objects" >&2
  exit 1
fi

mkdir -p "$(dirname "$output")"
rm -f "$output"
ar rcs "$output" "${objects[@]}"
echo "$output"
