# Unified static-musl host architecture build

This branch builds one NDK archive containing three independently runnable host-tool sets. The host tools use **static Linux-musl ELF executables**; directory tags are package identifiers and do not imply Bionic linkage.

## Host matrix

| `HOST_ARCH` | Package directory | Static-musl host triple | Sysroot |
|---|---|---|---|
| `aarch64` | `android-arm64` | `aarch64-unknown-linux-musl` | `prebuilts/build-tools/sysroots/aarch64-unknown-linux-musl` |
| `x86_64` | `linux-x86_64` | `x86_64-unknown-linux-musl` | `prebuilts/build-tools/sysroots/x86_64-unknown-linux-musl` |
| `armv7` | `android-armv7` | `arm-unknown-linux-musleabihf` | `prebuilts/build-tools/sysroots/arm-unknown-linux-musleabihf` |

Each host set must retain all four Android **target** ABIs:

- `arm64-v8a`
- `armeabi-v7a`
- `x86_64`
- `x86`

Host architecture and Android target ABI are separate dimensions. Do not reduce LLVM's backend list to the selected host architecture.

## Shared architecture selection

The architecture selector is `patches/host-env.sh`. It exports the same `HOST_ARCH`, `TERMUX_NDK_HOST_TAG`, `TERMUX_NDK_HOST_TRIPLE`, `TERMUX_NDK_SYSROOT`, and `CMAKE_PROCESSOR` to all build layers.

The AOSP LLVM Android and NDK patch sets are now shared, environment-driven patches:

- `patches/llvm_android/configs.py.patch` selects `hosts.Arch` from `TERMUX_NDK_HOST_ARCH` and determines whether the build is cross-compiling from the actual build machine.
- `patches/ndk/hosts.py.patch` maps Linux + CPU architecture to the correct prebuilt package tag.
- `patches/ndk/toolchains.py.patch` selects the matching static-musl triple from `TERMUX_NDK_HOST_TRIPLE`.
- `patches/llvm_android/base_builders.py.patch` keeps the AArch64, ARM, and X86 LLVM backends available while setting the selected host executable architecture.

Do not use the removed x86_64 / ARMv7 Android-Bionic patch variants. They conflicted with the static-musl Stage2 sysroots and link flags.

## Apply and validate patches

Each matrix entry uses its own clean AOSP checkout. The CI workflow applies the common patches separately for all three architecture environment values:

```bash
export TERMUX_NDK_HOST_ARCH=aarch64
export TERMUX_NDK_HOST_TRIPLE=aarch64-unknown-linux-musl

# Apply patches from the repository root of the corresponding clean source tree.
patch -p1 < patches/ndk/hosts.py.patch
patch -p1 < patches/ndk/toolchains.py.patch
patch -p1 < patches/llvm_android/builders.py.patch
patch -p1 < patches/llvm_android/base_builders.py.patch
patch -p1 < patches/llvm_android/configs.py.patch
```

Use `x86_64` with `x86_64-unknown-linux-musl`, or `armv7` with `arm-unknown-linux-musleabihf`, for the other matrix entries.

## Stage2 parameterization

`patches/build_stage2.sh` accepts one architecture per invocation:

```bash
HOST_ARCH=aarch64 bash patches/build_stage2.sh
HOST_ARCH=x86_64 bash patches/build_stage2.sh
HOST_ARCH=armv7 bash patches/build_stage2.sh
```

Each invocation uses separate build and install directories. The script parameterizes the LLVM runtime triple, sysroot, dependency install paths, compiler wrapper, Python paths, and CMake processor. It validates that architecture-specific compiler tools, Python libraries, sysroot, SWIG host executable, and static dependencies exist before configuring CMake.

The following inputs must be built separately for each host architecture:

- A Zig wrapper at `TOOLCHAIN/bin/{cc,c++,ld,objcopy,ar,ranlib,strip}` that actually targets the selected architecture.
- A matching static-musl sysroot.
- Static target-architecture dependency archives under `out/lib/*-$MUSL_TRIPLE-install`.
- A build-machine-native Python executable under `PYTHON_HOST_ROOT`.
- A target-architecture `libpythonX.Y.a` and matching headers under `PYTHON_TARGET_ROOT`, where `X.Y` is resolved from the pinned AOSP Linux Python prebuilt. The resolver rejects multiple header versions, missing `Python.h`/`pyconfig.h`, executable/header version mismatches, and conflicting overrides.
- A build-machine-native SWIG executable under `SWIG_HOST_EXECUTABLE`.
- Build-machine-native `llvm-tblgen`, `clang-tblgen`, and `lldb-tblgen` executables. Build these first for every Stage2 configuration with `bash patches/build_native_tools.sh`; CMake is explicitly configured with `CMAKE_SYSTEM_NAME=Linux`, so the script always supplies native TableGen tools through `LLVM_NATIVE_TOOL_DIR`.

The native Python executable and target Python archive are intentionally separate. An x86_64 Python static library must never be linked into an ARM64 or ARMv7 executable.

Override `TOOLCHAIN`, `SYSROOT`, `DEPS_PREFIX`, `PYTHON_HOST_ROOT`, `PYTHON_TARGET_ROOT`, `SWIG_HOST_EXECUTABLE`, `LLVM_PROFDATA_FILE`, `LLVM_ROOT`, `LLVM_SRC_DIR`, `BUILD_DIR`, and `INSTALL_PREFIX` when the build environment uses different paths. Stage2 now fails early if the profile data file is absent or empty.

## Runtime validation gates

`patches/validate_host_toolchain.sh` compiles C and C++ smoke programs, checks their ELF machine, rejects `PT_INTERP` and dynamic `NEEDED` entries, and executes them only when the build machine matches the target architecture.

`patches/validate_stage2_install.sh` audits installed executables for the expected ELF machine and rejects dynamic interpreters or shared-library dependencies.

A successful cross-compile plus ELF inspection is not a substitute for executing binaries on real devices. Final validation must include Android/Termux and proot Linux on each supported host architecture, plus NDK application builds for all four target ABIs.

## Current status and blockers

- The Stage2 entry point is architecture-parameterized.
- LLVM and NDK host selection now use one shared static-musl configuration instead of mixing Android/Bionic triples with Musl sysroots.
- The malformed LLVM base-builder patch hunk has been corrected.
- The upstream patch-applicability workflow passed for all three architecture selections: [run 44298980789](https://github.com/msmt2018/termux-ndk/actions/runs/44298980789). It applied the NDK and LLVM Android patches to clean AOSP checkouts, compiled the modified Python modules, and exercised NDK host-tag / host-triple selection.
- The shell validation workflow passed Bash syntax, ShellCheck, unified-diff hunk counts, and host selector checks: [run 44299210514](https://github.com/msmt2018/termux-ndk/actions/runs/44299210514).
- Compiler wrappers, per-architecture sysroots, Python target libraries, SWIG host tool, and dependency archives still need to exist before Stage2 can configure and build.
- No full LLVM Stage2 build, NDK integration build, all-four-ABI sample build, or real-device runtime test is claimed as passed.

The release gate remains one unified NDK archive containing all three host tool sets, each able to produce binaries for all four Android target ABIs. Do not publish a Draft Release until every architecture and target ABI passes its build and runtime tests.
