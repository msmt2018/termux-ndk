# Android host architecture patch sets

These patch files are **mutually exclusive alternatives**. Apply exactly one host patch set to a fresh checkout of the matching AOSP NDK / llvm_android source revision. Do not apply the x86_64 and ARMv7 patches on top of the AArch64 patch: all three intentionally replace the same Linux-host configuration.

## Patch matrix

| NDK prebuilt directory | Host compiler triple | NDK host GCC-style triple | Patch files |
|---|---|---|---|
| `linux-x86_64` | `x86_64-linux-android28` | `x86_64-linux-android` | `ndk/toolchains-x86_64.py.patch`, `llvm_android/configs-x86_64.py.patch` |
| `android-arm64` | `aarch64-linux-android28` | `aarch64-linux-android` | Existing `ndk/toolchains.py.patch`, `llvm_android/configs.py.patch` |
| `android-armv7` | `armv7a-linux-androideabi21` | `arm-linux-androideabi` | `ndk/toolchains-armv7.py.patch`, `llvm_android/configs-armv7.py.patch` |

The ARMv7 host uses the ARMv7-A instruction set and API 21 as its initial host compatibility floor. This is a build-time policy and must be confirmed against the final runtime dependencies and actual Android 32-bit devices before release.

## Important separation: host versus target

These patches change the **host executable architecture** of the NDK build tools. They must not remove or replace the NDK's Android target ABIs. Every host package must retain the complete target set:

- `arm64-v8a`
- `armeabi-v7a`
- `x86_64`
- `x86`

The LLVM target/sysroot configuration is shared across host variants. Do not set LLVM's only target to the host architecture.

## Apply

Run each patch set against its own clean source checkout, for example:

```bash
# x86_64 host
patch -p1 < patches/ndk/toolchains-x86_64.py.patch
patch -p1 < patches/llvm_android/configs-x86_64.py.patch

# ARMv7 host (use a separate clean checkout)
patch -p1 < patches/ndk/toolchains-armv7.py.patch
patch -p1 < patches/llvm_android/configs-armv7.py.patch
```

The existing unsuffixed patch files remain the AArch64 host variant.

## Known follow-up required before building

The current `patches/build_stage2.sh` is still hard-coded to `aarch64-unknown-linux-musl` and AArch64-specific dependency/sysroot paths. These patch sets only establish the NDK and llvm_android host-triple/configuration layer; they do **not** make stage2 multi-architecture yet. Stage2 must be parameterized separately for x86_64 and ARMv7, and the produced binaries must be checked with `readelf -h`, `readelf -l`, and runtime smoke tests on real Android devices / Termux and proot environments.

Also verify the actual upstream source revision before applying: the patch context is based on the source layout represented by the repository's existing AArch64 patches. AOSP source revisions can change these contexts.


## Runtime ABI gate: do not conflate Android triples with static-musl builds

The patch matrix above is **provisional** until the runtime ABI is made consistent with the stage2 compiler configuration.

The current `patches/build_stage2.sh` configures:

- `CMAKE_SYSTEM_NAME=Linux`
- a Zig-based compiler wrapper
- `-static` compile/link flags
- `*-unknown-linux-musl` as `LLVM_DEFAULT_TARGET_TRIPLE`, `LLVM_BUILTIN_TARGETS`, and `LLVM_RUNTIME_TARGETS`
- a matching `prebuilts/build-tools/sysroots/*-unknown-linux-musl` sysroot and per-target static dependency archives.

By contrast, the provisional NDK / llvm_android patches above set Linux host compiler triples to `*-linux-android*` or `*-linux-androideabi*`. Those are Bionic/Android triples. A triple alone does not make a binary Android-runnable: the compiler and every linked dependency must use a compatible Android sysroot, API level, and Bionic runtime.

There are therefore two distinct implementation routes:

1. **Static musl host tools:** retain Linux-musl triples throughout stage2 and the host-tool build configuration, build fully static ELF executables for each CPU architecture, then verify that the resulting executables run on the intended Android kernels and proot environments. The NDK packaging directory names (`linux-x86_64`, `android-arm64`, `android-armv7`) are labels only and must not be treated as proof of the runtime ABI.
2. **Bionic host tools:** use Android triples consistently, provide the matching Android sysroot/API level to every compiler and dependency build, and link against Bionic. The current static-musl stage2 flags and sysroots cannot simply be reused for this route.

Do not mix the two routes in one build. In particular, do not change only `toolchains.py` / `configs.py` triples while leaving stage2 and its dependency archives on musl, and do not claim an Android/Bionic build based only on an `android-*` output directory name.

### Current verified status

- Unified-diff hunk counts were checked for the four architecture-specific patch files.
- No upstream AOSP source-tree `patch --dry-run` / `git apply --check` has been completed.
- No x86_64 or ARMv7 stage2 build has been completed.
- No ELF interpreter / dynamic dependency audit or on-device runtime test has been completed.
- The existing AArch64 path is the only current implementation baseline; it must also pass the same ABI audit before being treated as release-ready.

The next implementation step is to choose one runtime route, then parameterize the entire stage2 dependency graph and host configuration around it. The required build inputs are the per-architecture compiler wrapper, sysroot, dependency install prefix, runtime triple, and output directory; these must all agree.


## Stage2 parameterization added

`patches/build_stage2.sh` now accepts one architecture per invocation:

| `HOST_ARCH` | Static-musl runtime triple | Default Zig wrapper |
|---|---|---|
| `aarch64` | `aarch64-unknown-linux-musl` | `$HOME/opt/zig-as-llvm` |
| `x86_64` | `x86_64-unknown-linux-musl` | `$HOME/opt/zig-as-llvm-x86_64` |
| `armv7` | `arm-unknown-linux-musleabihf` | `$HOME/opt/zig-as-llvm-armv7` |

Each invocation uses a separate build directory and install prefix. The script now parameterizes the LLVM runtime triple, sysroot, dependency install paths, compiler wrapper, Python paths, and CMake processor. It also fails early when architecture-specific dependencies are missing.

Example invocations:

```bash
HOST_ARCH=aarch64 ./patches/build_stage2.sh
HOST_ARCH=x86_64 ./patches/build_stage2.sh
HOST_ARCH=armv7 ./patches/build_stage2.sh
```

The following inputs must exist for each architecture before stage2 can configure:

- A Zig wrapper at `TOOLCHAIN/bin/{cc,c++,ld,objcopy,ar,ranlib,strip}` that actually targets the selected architecture.
- The matching `prebuilts/build-tools/sysroots/$MUSL_TRIPLE` sysroot.
- Matching static dependency installs under `out/lib/*-$MUSL_TRIPLE-install`.
- A build-machine-native Python executable under `PYTHON_HOST_ROOT`.
- A target-architecture `libpython3.12.a` and headers under `PYTHON_TARGET_ROOT`. The host Python executable and target Python library are intentionally separate; linking the x86_64 host Python archive into an ARM64 or ARMv7 executable would be an architecture mismatch.

Override `TOOLCHAIN`, `SYSROOT`, `DEPS_PREFIX`, `PYTHON_HOST_ROOT`, `PYTHON_TARGET_ROOT`, `LLVM_ROOT`, `LLVM_SRC_DIR`, `BUILD_DIR`, or `INSTALL_PREFIX` when the build environment uses different locations.

### Integration blocker still open

Stage2 now follows the static-musl route, but the provisional `ndk/toolchains*.py.patch` and `llvm_android/configs*.py.patch` files still contain Android/Bionic triples. They have **not** yet been reconciled with the static-musl host-tool output. Do not run the complete NDK integration build by mixing these configurations. The next patching pass must align the NDK and llvm_android host configuration with the selected runtime ABI, or deliberately switch stage2 to a Bionic sysroot build.

No architecture-specific stage2 build has been run yet. The parameterization is a source change, not evidence that the three compilers, dependency archives, or resulting executables are already available or working.
