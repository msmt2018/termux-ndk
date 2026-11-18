#!/usr/bin/env bash
# Source this file to select one complete static-musl host configuration:
#   source patches/host-env.sh aarch64
#   source patches/host-env.sh x86_64
#   source patches/host-env.sh armv7
#
# The selected variables are exported so the LLVM and NDK build layers use
# exactly the same host tag, triple, sysroot and toolchain directory.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "error: source this file instead of executing it" >&2
    exit 2
fi

termux_ndk_select_host() {
    local selected="${1:-${HOST_ARCH:-aarch64}}"

    case "${selected}" in
        aarch64)
            HOST_ARCH="aarch64"
            TERMUX_NDK_HOST_TAG="android-arm64"
            TERMUX_NDK_HOST_TRIPLE="aarch64-unknown-linux-musl"
            CMAKE_PROCESSOR="aarch64"
            DEFAULT_TOOLCHAIN="$HOME/opt/zig-as-llvm"
            ;;
        x86_64)
            HOST_ARCH="x86_64"
            TERMUX_NDK_HOST_TAG="linux-x86_64"
            TERMUX_NDK_HOST_TRIPLE="x86_64-unknown-linux-musl"
            CMAKE_PROCESSOR="x86_64"
            DEFAULT_TOOLCHAIN="$HOME/opt/zig-as-llvm-x86_64"
            ;;
        armv7)
            HOST_ARCH="armv7"
            TERMUX_NDK_HOST_TAG="android-armv7"
            TERMUX_NDK_HOST_TRIPLE="arm-unknown-linux-musleabihf"
            CMAKE_PROCESSOR="arm"
            DEFAULT_TOOLCHAIN="$HOME/opt/zig-as-llvm-armv7"
            ;;
        *)
            echo "error: unsupported HOST_ARCH '${selected}' (expected aarch64, x86_64 or armv7)" >&2
            return 2
            ;;
    esac

    LLVM_ROOT="${LLVM_ROOT:-$HOME/proj/llvm-toolchain}"
    TERMUX_NDK_SYSROOT="${TERMUX_NDK_SYSROOT:-${SYSROOT:-${LLVM_ROOT}/prebuilts/build-tools/sysroots/${TERMUX_NDK_HOST_TRIPLE}}}"

    export HOST_ARCH TERMUX_NDK_HOST_TAG TERMUX_NDK_HOST_TRIPLE
    export TERMUX_NDK_SYSROOT CMAKE_PROCESSOR DEFAULT_TOOLCHAIN LLVM_ROOT
}

termux_ndk_select_host "${1:-${HOST_ARCH:-aarch64}}"
