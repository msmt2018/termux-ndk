#!/usr/bin/env bash
set -Eeuo pipefail

# Reject cross-architecture static archives before CMake can accidentally
# link a dependency built for the build machine or another host variant.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOST_ARCH="${HOST_ARCH:-aarch64}"
LLVM_ROOT="${LLVM_ROOT:-$HOME/proj/llvm-toolchain}"
# shellcheck source=patches/host-env.sh
source "${SCRIPT_DIR}/host-env.sh" "${HOST_ARCH}"

DEPS_PREFIX="${DEPS_PREFIX:-${LLVM_ROOT}/out/lib}"
PYTHON_TARGET_ROOT="${PYTHON_TARGET_ROOT:-${LLVM_ROOT}/out/python-${TERMUX_NDK_HOST_TRIPLE}-install}"
: "${PYTHON_VERSION:?error: source patches/resolve_python_version.sh before validating Stage2 inputs}"

case "${HOST_ARCH}" in
    aarch64) EXPECTED_MACHINE="AArch64" ;;
    x86_64) EXPECTED_MACHINE="Advanced Micro Devices X86-64" ;;
    armv7) EXPECTED_MACHINE="ARM" ;;
    *) echo "error: unsupported HOST_ARCH '${HOST_ARCH}'" >&2; exit 2 ;;
esac

command -v readelf >/dev/null 2>&1 || {
    echo "error: readelf is required to inspect static archives" >&2
    exit 3
}

ARCHIVES=(
    "${DEPS_PREFIX}/libz-${TERMUX_NDK_HOST_TRIPLE}-install/lib/libz.a"
    "${DEPS_PREFIX}/libxml2-${TERMUX_NDK_HOST_TRIPLE}-install/lib/libxml2.a"
    "${DEPS_PREFIX}/libzstd-${TERMUX_NDK_HOST_TRIPLE}-install/lib/libzstd.a"
    "${DEPS_PREFIX}/liblzma-${TERMUX_NDK_HOST_TRIPLE}-install/lib/liblzma.a"
    "${DEPS_PREFIX}/libedit-${TERMUX_NDK_HOST_TRIPLE}-install/lib/libedit.a"
    "${DEPS_PREFIX}/libncurses-${TERMUX_NDK_HOST_TRIPLE}-install/lib/libncurses.a"
    "${DEPS_PREFIX}/libncurses-${TERMUX_NDK_HOST_TRIPLE}-install/lib/libform.a"
    "${DEPS_PREFIX}/libncurses-${TERMUX_NDK_HOST_TRIPLE}-install/lib/libpanel.a"
    "${PYTHON_TARGET_ROOT}/lib/libpython${PYTHON_VERSION}.a"
)

checked=0
for archive in "${ARCHIVES[@]}"; do
    [[ -s "${archive}" ]] || {
        echo "error: missing or empty target static archive: ${archive}" >&2
        exit 4
    }
    headers="$(readelf -h "${archive}" 2>/dev/null)" || {
        echo "error: readelf could not inspect static archive: ${archive}" >&2
        exit 5
    }
    machines="$(awk -F 'Machine:[[:space:]]*' '/Machine:/ { print $2 }' <<< "${headers}")"
    [[ -n "${machines}" ]] || {
        echo "error: no ELF object members found in static archive: ${archive}" >&2
        exit 6
    }
    while IFS= read -r machine; do
        [[ "${machine}" == "${EXPECTED_MACHINE}" ]] || {
            echo "error: architecture mismatch in ${archive}: expected ${EXPECTED_MACHINE}, found ${machine}" >&2
            exit 7
        }
    done <<< "${machines}"
    checked=$((checked + 1))
done

echo "PASS: verified ELF machine for all ${checked} target static archives (${EXPECTED_MACHINE})."
