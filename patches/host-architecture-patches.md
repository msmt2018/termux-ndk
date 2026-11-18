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
