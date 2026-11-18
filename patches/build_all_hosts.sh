#!/usr/bin/env bash
set -Eeuo pipefail

# Preflight all three host variants before spending time on native TableGen or
# any Stage2 build. Then build native generators once and Stage2 sequentially.
#
# Per-host overrides:
#   TOOLCHAIN_AARCH64 / TOOLCHAIN_X86_64 / TOOLCHAIN_ARMV7
#   SYSROOT_AARCH64 / SYSROOT_X86_64 / SYSROOT_ARMV7
#   PYTHON_TARGET_ROOT_AARCH64 / PYTHON_TARGET_ROOT_X86_64 / PYTHON_TARGET_ROOT_ARMV7
#
# Shared overrides are the same as build_stage2.sh.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LLVM_ROOT="${LLVM_ROOT:-$HOME/proj/llvm-toolchain}"
LLVM_SRC_DIR="${LLVM_SRC_DIR:-${LLVM_ROOT}/out/llvm-project/llvm}"
DEPS_PREFIX="${DEPS_PREFIX:-${LLVM_ROOT}/out/lib}"
PYTHON_HOST_ROOT="${PYTHON_HOST_ROOT:-${LLVM_ROOT}/prebuilts/python/linux-x86}"
# Resolve once from the pinned AOSP prebuilt layout and export to every host.
# shellcheck source=patches/resolve_python_version.sh
source "${SCRIPT_DIR}/resolve_python_version.sh"
SWIG_HOST_EXECUTABLE="${SWIG_HOST_EXECUTABLE:-${LLVM_ROOT}/out/host-tools/swig-install/bin/swig}"
PROFDATA_FILE="${LLVM_PROFDATA_FILE:-${LLVM_ROOT}/out/r563880.profdata}"
NATIVE_BUILD_DIR="${NATIVE_BUILD_DIR:-${LLVM_ROOT}/out/native-tools-build}"
LLVM_NATIVE_TOOL_DIR="${LLVM_NATIVE_TOOL_DIR:-${NATIVE_BUILD_DIR}/bin}"

export LLVM_ROOT LLVM_SRC_DIR DEPS_PREFIX PYTHON_HOST_ROOT
export SWIG_HOST_EXECUTABLE LLVM_PROFDATA_FILE="${PROFDATA_FILE}"
export NATIVE_BUILD_DIR LLVM_NATIVE_TOOL_DIR

host_overrides() {
    local arch="$1"
    case "${arch}" in
        aarch64)
            TOOLCHAIN_OVERRIDE="${TOOLCHAIN_AARCH64:-}"
            SYSROOT_OVERRIDE="${SYSROOT_AARCH64:-}"
            PYTHON_OVERRIDE="${PYTHON_TARGET_ROOT_AARCH64:-}"
            ;;
        x86_64)
            TOOLCHAIN_OVERRIDE="${TOOLCHAIN_X86_64:-}"
            SYSROOT_OVERRIDE="${SYSROOT_X86_64:-}"
            PYTHON_OVERRIDE="${PYTHON_TARGET_ROOT_X86_64:-}"
            ;;
        armv7)
            TOOLCHAIN_OVERRIDE="${TOOLCHAIN_ARMV7:-}"
            SYSROOT_OVERRIDE="${SYSROOT_ARMV7:-}"
            PYTHON_OVERRIDE="${PYTHON_TARGET_ROOT_ARMV7:-}"
            ;;
        *)
            echo "error: unsupported host architecture: ${arch}" >&2
            return 2
            ;;
    esac
}

preflight_host() (
    local arch="$1"
    local toolchain_override="$2"
    local sysroot_override="$3"
    local python_override="$4"

    export HOST_ARCH="${arch}"
    unset TERMUX_NDK_SYSROOT
    # shellcheck source=patches/host-env.sh
    source "${SCRIPT_DIR}/host-env.sh" "${HOST_ARCH}"

    TOOLCHAIN="${toolchain_override:-${DEFAULT_TOOLCHAIN}}"
    SYSROOT="${sysroot_override:-${TERMUX_NDK_SYSROOT}}"
    PYTHON_TARGET_ROOT="${python_override:-${LLVM_ROOT}/out/python-${TERMUX_NDK_HOST_TRIPLE}-install}"

    for required in \
        "${LLVM_SRC_DIR}/CMakeLists.txt" \
        "${PYTHON_HOST_EXECUTABLE}" \
        "${SWIG_HOST_EXECUTABLE}" \
        "${PROFDATA_FILE}" \
        "${SYSROOT}" \
        "${PYTHON_TARGET_ROOT}/include/python${PYTHON_VERSION}" \
        "${PYTHON_TARGET_ROOT}/lib/libpython${PYTHON_VERSION}.a" \
        "${DEPS_PREFIX}/libz-${TERMUX_NDK_HOST_TRIPLE}-install/include" \
        "${DEPS_PREFIX}/libxml2-${TERMUX_NDK_HOST_TRIPLE}-install/include/libxml2" \
        "${DEPS_PREFIX}/libzstd-${TERMUX_NDK_HOST_TRIPLE}-install/include" \
        "${DEPS_PREFIX}/liblzma-${TERMUX_NDK_HOST_TRIPLE}-install/include" \
        "${DEPS_PREFIX}/libedit-${TERMUX_NDK_HOST_TRIPLE}-install/include" \
        "${DEPS_PREFIX}/libncurses-${TERMUX_NDK_HOST_TRIPLE}-install/include"; do
        [[ -e "${required}" ]] || {
            echo "error: ${arch} preflight input missing: ${required}" >&2
            exit 10
        }
    done
    [[ -x "${PYTHON_HOST_EXECUTABLE}" ]] || {
        echo "error: native Python is not executable: ${PYTHON_HOST_EXECUTABLE}" >&2
        exit 11
    }
    [[ -x "${SWIG_HOST_EXECUTABLE}" ]] || {
        echo "error: native SWIG is not executable: ${SWIG_HOST_EXECUTABLE}" >&2
        exit 12
    }
    [[ -s "${PROFDATA_FILE}" ]] || {
        echo "error: LLVM profile data is missing or empty: ${PROFDATA_FILE}" >&2
        exit 13
    }

    HOST_ARCH="${HOST_ARCH}" TOOLCHAIN="${TOOLCHAIN}" SYSROOT="${SYSROOT}" \
        bash "${SCRIPT_DIR}/validate_host_toolchain.sh"
    HOST_ARCH="${HOST_ARCH}" DEPS_PREFIX="${DEPS_PREFIX}" PYTHON_TARGET_ROOT="${PYTHON_TARGET_ROOT}" \
        bash "${SCRIPT_DIR}/validate_stage2_inputs.sh"

    printf 'PASS: preflight complete for %s (%s)\n' "${arch}" "${TERMUX_NDK_HOST_TRIPLE}"
)

run_stage2_host() {
    local arch="$1"
    host_overrides "${arch}"
    local toolchain_override="${TOOLCHAIN_OVERRIDE}"
    local sysroot_override="${SYSROOT_OVERRIDE}"
    local python_override="${PYTHON_OVERRIDE}"

    export HOST_ARCH="${arch}"
    unset TERMUX_NDK_SYSROOT
    # shellcheck source=patches/host-env.sh
    source "${SCRIPT_DIR}/host-env.sh" "${HOST_ARCH}"

    export TOOLCHAIN="${toolchain_override:-${DEFAULT_TOOLCHAIN}}"
    export SYSROOT="${sysroot_override:-${TERMUX_NDK_SYSROOT}}"
    export PYTHON_TARGET_ROOT="${python_override:-${LLVM_ROOT}/out/python-${TERMUX_NDK_HOST_TRIPLE}-install}"
    export BUILD_STAGE2=1

    bash "${SCRIPT_DIR}/build_stage2.sh"
}

for arch in aarch64 x86_64 armv7; do
    host_overrides "${arch}"
    preflight_host "${arch}" "${TOOLCHAIN_OVERRIDE}" "${SYSROOT_OVERRIDE}" "${PYTHON_OVERRIDE}"
done

echo "All three host variants passed preflight; building native TableGen tools once."
bash "${SCRIPT_DIR}/build_native_tools.sh"

for arch in aarch64 x86_64 armv7; do
    echo "===== Building Stage2 host: ${arch} ====="
    run_stage2_host "${arch}"
done

echo "PASS: all three Stage2 host builds completed and passed installation audits."
