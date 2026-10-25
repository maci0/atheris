# Python 3.15 maintenance build

Based on upstream google/atheris commit e36da74cf42b5834c4e31d7cabb58d796695d29f.
The source and Apache-2.0 license remain available in this repository. The local
version `3.1.0+relumea.2` distinguishes these artifacts from upstream 3.1.0.
`3.1.0+relumea.1` linked the build machine's libFuzzer archive and is not a
generic x86_64 wheel.

Python 3.15 retains the jump and code-object conventions used by the existing
instrumentor. Inline cache lengths are read from the interpreter, including the
new RESUME, GET_ITER and CALL_FUNCTION_EX caches. The self-consistency test now
accepts Mapping metadata, since Python 3.15 exposes a frozendict. A regression
executes an instrumented loop and star call repeatedly and checks coverage.
The interpreter support bound and CI matrix explicitly include 3.15.

Build with CPython 3.15.1 and the build-system dependencies pinned in
pyproject.toml, on Ubuntu 24.04 (or another system whose glibc and libstdc++
are no newer than that image). Do not build the wheel on a newer host: the
linked glibc and libstdc++ symbol versions become the wheel's floor.

Clang supplies the compiler. The libFuzzer archive is not the one installed
beside that Clang. `setup_utils/build_portable_libfuzzer.sh` compiles the
pinned compiler-rt `lib/fuzzer` sources (LLVM 23.1.3, without `FuzzerMain.cpp`)
with `-march=x86-64 -mtune=generic` and the script is what `LIBFUZZER_LIB`
must point at. The build drops libFuzzer's `target("popcnt")` compare
specialization, which upstream calls directly, so the objects stay on the
SSE2 baseline instead of requiring POPCNT. The same architecture flags are passed for the native
extensions, the libFuzzer upgrade wrapper, and the merged sanitizer objects.
pybind11 3.1.0 builds against the actual CPython 3.15 headers. No stable-ABI
compatibility override is used. Set SOURCE_DATE_EPOCH to the source commit
timestamp, TZ=UTC, LC_ALL=C, PYTHONHASHSEED=0 and use -g0 plus
-ffile-prefix-map for source and build-environment paths when independently
comparing wheels from different paths.

`setup_utils/audit_wheel_abi.sh` records the highest GLIBC and GLIBCXX
symbol versions of the extension modules, the bundled libFuzzer archive,
and the merged sanitizer objects, and whether their text contains AVX,
AVX-512, or POPCNT. A baseline wheel has none of those. The script fails
if objdump, readelf, or ar is missing, if a wheel lacks that set, or if it
is pointed at an empty directory. `--self-check` covers the empty input.
The measured floors belong in the release provenance; a previous wheel's
floor is not a promise for this one.

Run the upstream version_dependent, instrument_bytecode, fuzzed_data_provider,
instrument_all, regex, string-hook, fuzz integration and custom mutation tests.
The consumer qualification also runs all six unchanged Resembl fuzzers against
this native extension and real libFuzzer, requiring observed coverage.
