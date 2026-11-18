# Termux NDK

A development fork of the Android NDK toolchain build intended to produce one unified NDK archive with multiple host executables.

## Planned host environments

- `linux-x86_64`
- `android-arm64`
- `android-armv7`

Each host toolchain is intended to support all four Android target ABIs:

- `arm64-v8a`
- `armeabi-v7a`
- `x86_64`
- `x86`

The release goal is **one NDK archive containing all three host toolchains**, not separate NDK archives per target ABI.

## Runtime model

The current Stage2 direction is static Linux-musl host executables. This is distinct from building Bionic-linked Android executables: the compiler triple, sysroot, dependency archives, and final ELF runtime must all remain consistent. Android host directory names are package tags, not proof of Bionic linkage.

## Current development status

The `multi-host-architecture-patches` branch contains:

- a parameterized LLVM Stage2 entry point for AArch64, x86_64, and ARMv7;
- a static C/C++ compiler smoke-test gate with ELF architecture and interpreter checks;
- a shared host environment selector for consistent host tags, triples, and sysroots;
- NDK host-tag detection for x86_64, Android ARM64, and Android ARMv7;
- LLVM Musl host configuration variants and automated workflows that apply the six architecture patch sets to pinned AOSP source trees and compile the modified Python modules.

These are source-level changes. The three compiler wrappers, architecture-specific sysroots and dependency archives still need to be built and tested. Full NDK integration, all-four-ABI application builds, and on-device Termux/proot runtime tests have not yet passed. No release archive is claimed to be ready.

## Building

See [host architecture and build status](patches/host-architecture-patches.md) for the current patch matrix, prerequisites, validation commands, and remaining integration blockers.

The original Android NDK build references remain useful for understanding the upstream project:

- [Android Clang/LLVM Toolchain Build Instructions](https://android.googlesource.com/toolchain/llvm_android/+/main/BUILD.md)
- [NDK Toolchains Build Instructions](https://github.com/android/ndk/blob/main/docs/Building.md)
- [Example Android native projects](build-app/)
