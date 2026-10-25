# Python 3.15 maintenance build

Based on upstream google/atheris commit e36da74cf42b5834c4e31d7cabb58d796695d29f.
The source and Apache-2.0 license remain available in this repository. The local
version `3.1.0+relumea.1` distinguishes these artifacts from upstream 3.1.0.

Python 3.15 retains the jump and code-object conventions used by the existing
instrumentor. Inline cache lengths are read from the interpreter, including the
new RESUME, GET_ITER and CALL_FUNCTION_EX caches. The self-consistency test now
accepts Mapping metadata, since Python 3.15 exposes a frozendict. A regression
executes an instrumented loop and star call repeatedly and checks coverage.
The interpreter support bound and CI matrix explicitly include 3.15.

Build with CPython 3.15.1 and the build-system dependencies pinned in
pyproject.toml. Clang supplies the real libFuzzer runtime; pybind11 3.1.0 builds
against the actual CPython 3.15 headers. No stable-ABI compatibility override is
used. Set SOURCE_DATE_EPOCH to the source commit timestamp, TZ=UTC,
LC_ALL=C, PYTHONHASHSEED=0 and use -g0 plus -ffile-prefix-map for source/build
environment paths when independently comparing wheels from different paths.

Run the upstream version_dependent, instrument_bytecode, fuzzed_data_provider,
instrument_all, regex, string-hook, fuzz integration and custom mutation tests.
The consumer qualification also runs all six unchanged Resembl fuzzers against
this native extension and real libFuzzer, requiring observed coverage.
