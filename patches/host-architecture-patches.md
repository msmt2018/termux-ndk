# Multi-host NDK architecture and build status

## Target package design

Produce **one unified NDK archive** containing three host toolchain variants. Every host variant must retain all four Android application target ABIs.

| Host package tag | Host CPU | Static-musl host triple | Stage2 Zig wrapper default |
|---|---|---|---|
| `linux-x86_64` | x86-64 | `x86_64-unknown-linux-musl` | `$HOME/opt/zig-as-llvm-x86_64` |
| `android-arm64` | AArch64 | `aarch64-unknown-linux-musl` | `$HOME/opt/zig-as-llvm` |
| `android-armv7` | ARMv7-A hard-float | `arm-unknown-linux-musleabihf` | `$HOME/opt/zig-as-llvm-armv7` |

Android target ABIs remain:

- `arm64-v8a`
- `armeabi-v7a`
- `x86_64`
- `x86`

The `android-arm64` and `android-armv7` names are NDK host package tags. They do **not** mean that these executables are Bionic-linked. The current runtime strategy is fully static Linux-musl executables so that the same host tools can run in Termux and compatible proot Linux environments. ELF and real-device tests are still required.

## Patch composition

Apply one architecture variant to a clean upstream source tree. Do not apply multiple architecture variants to the same checkout.

Common NDK patch:

- `patches/ndk/hosts.py.patch`: selects `linux-x86_64`, `android-arm64`, or `android-armv7` using `TERMUX_NDK_HOST_TAG` or the actual Linux machine architecture.

Architecture-specific NDK patch:

| Host | Patch |
|---|---|
| x86-64 | `patches/ndk/toolchains-x86_64.py.patch` |
| AArch64 | `patches/ndk/toolchains.py.patch` |
| ARMv7 | `patches/ndk/toolchains-armv7.py.patch` |

The NDK patches set the corresponding Musl host triple, require `TERMUX_NDK_SYSROOT`, reject a missing sysroot directory, use the selected sysroot's `lib` and `usr/lib` search paths, and avoid adding the stage0 Clang `lib64` directory to target-host links.

Common LLVM Android patches:

- `patches/llvm_android/base_builders.py.patch`: derives the host triple and LLVM host architecture from the selected config; builds the `AArch64;ARM;X86` backends required by all four Android target ABIs.
- `patches/llvm_android/builders.py.patch`: adds the existing profile warning suppression.

Architecture-specific LLVM Android config patch:

| Host | Patch |
|---|---|
| x86-64 | `patches/llvm_android/configs-x86_64.py.patch` |
| AArch64 | `patches/llvm_android/configs.py.patch` |
| ARMv7 | `patches/llvm_android/configs-armv7.py.patch` |

These variants use upstream `LinuxMuslHostConfig`, select the corresponding `hosts.Arch`, and set `is_cross_compiling` according to the build machine architecture. The generic glibc `LinuxConfig` is not repurposed as an Android/Bionic configuration. The old global `GCC_ROOT` override patch was removed because `LinuxMuslConfig` already provides its own sysroot, library directories, and binary directories.

## Shared host environment

`patches/host-env.sh` is the single source of truth for host package tag, Musl triple, default Zig wrapper, CMake processor, and sysroot path.

Source it in the same shell before building a host variant:

```bash
source patches/host-env.sh aarch64
# or: x86_64 / armv7
```

It exports:

- `HOST_ARCH`
- `TERMUX_NDK_HOST_TAG`
- `TERMUX_NDK_HOST_TRIPLE`
- `TERMUX_NDK_SYSROOT`
- `CMAKE_PROCESSOR`
- `DEFAULT_TOOLCHAIN`
- `LLVM_ROOT`

For CI cross-builds, explicitly select the desired architecture. Machine auto-detection in `hosts.py.patch` is intended for runtime selection when a user launches the packaged NDK on their device.

Override `LLVM_ROOT`, `SYSROOT`, or `TERMUX_NDK_SYSROOT` before sourcing if the workspace uses non-default paths.

## Stage2 build entry

`patches/build_stage2.sh` now accepts one host architecture per invocation:

```bash
HOST_ARCH=aarch64 bash patches/build_stage2.sh
HOST_ARCH=x86_64 bash patches/build_stage2.sh
HOST_ARCH=armv7 bash patches/build_stage2.sh
```

Each architecture uses a separate build directory and install prefix. The script parameterizes the compiler wrapper, runtime triple, sysroot, dependency paths, Python paths, and CMake processor. It performs preflight checks before invoking CMake.

The compiler smoke test can also be run independently:

```bash
HOST_ARCH=aarch64 bash patches/validate_host_toolchain.sh
HOST_ARCH=x86_64 bash patches/validate_host_toolchain.sh
HOST_ARCH=armv7 bash patches/validate_host_toolchain.sh
```

It checks the wrapper tools, `cc -dumpmachine`, static C and C++ compilation, ELF machine type, and absence of a PT_INTERP program header. It executes the test binaries only when the build machine matches the selected architecture.

### Build-time tools versus target libraries

Cross builds must not try to execute target-architecture tools on the x86-64 build runner:

- `Python3_EXECUTABLE` is build-machine-native Python.
- `Python3_LIBRARY` and Python headers are for the selected target architecture.
- `SWIG_EXECUTABLE` is now build-machine-native and configured through `SWIG_HOST_EXECUTABLE` (default: `out/host-tools/swig-install/bin/swig`).
- Zlib, LibXml2, Zstd, LZMA, LibEdit, Curses, and Python static libraries are target-architecture inputs.

LLVM/Clang/LLDB TableGen executables are also build-time host tools. A verified native TableGen bootstrap path has not yet been added for cross-building AArch64 and ARMv7 from x86-64. This must be solved before those Stage2 builds can be considered complete.

### Required target dependencies

For each Musl triple, the Stage2 preflight expects target-architecture static installs under `DEPS_PREFIX`:

- zlib
- libxml2
- zstd
- liblzma
- libedit
- ncurses (ncurses, form, and panel archives)
- Python 3.12 static library and headers

The Python interpreter and SWIG executable are separate native build-machine tools. Do not build them for the target architecture and then try to execute them during the cross build.

The repository currently contains the Stage2 consumer and prerequisite checks, but not a complete, verified three-architecture dependency bootstrap pipeline. The compiler wrappers, sysroots, dependency archives, and native TableGen tools must be supplied before a real Stage2 build can run.

## Automated validation

Two GitHub Actions workflows are present:

- `.github/workflows/host-script-validation.yml`: Bash syntax, ShellCheck, patch hunk counts, host environment mappings, and unsupported architecture behavior.
- `.github/workflows/upstream-patch-applicability.yml`: applies each of the three LLVM Android patch sets to a clean checkout of `mirror-goog-llvm-r563880-release`, and each of the three NDK host patch sets to a clean checkout of `platform/ndk` main; then runs Python syntax compilation on the modified modules.

The upstream patch-application workflow has passed for all six architecture variants. This proves patch applicability and Python syntax against those source snapshots, not that LLVM or the NDK has been built.

## Remaining release gates

1. Build or provide the three Zig compiler wrappers and matching Musl sysroots.
2. Build all target-architecture static dependencies and the target Python library.
3. Bootstrap native LLVM/Clang/LLDB TableGen tools for cross builds.
4. Run Stage2 separately for AArch64, x86-64, and ARMv7.
5. Audit every produced ELF with `readelf -h`, `readelf -l`, and dynamic dependency checks; confirm static linking and expected machine types.
6. Build sample C, C++, CMake, ndk-build, and JNI Android projects using each host toolchain, exercising all four Android target ABIs.
7. Run the host tools on actual Android/Termux devices and supported proot environments.
8. Assemble and test one unified NDK archive containing all three host toolchain directories.

No Stage2 build, four-ABI integration test, on-device runtime test, or release archive is claimed to have passed yet.
