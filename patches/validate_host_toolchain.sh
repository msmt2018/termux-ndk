#!/usr/bin/env bash
set -Eeuo pipefail

# Validate one complete static-musl host compiler wrapper before starting the
# expensive LLVM stage2 build. This validates compiler output, not NDK packaging.
#
# Usage:
#   HOST_ARCH=aarch64 ./patches/validate_host_toolchain.sh
#   HOST_ARCH=x86_64 TOOLCHAIN=/path/to/wrapper ./patches/validate_host_toolchain.sh
#   HOST_ARCH=armv7 TOOLCHAIN=/path/to/wrapper ./patches/validate_host_toolchain.sh

HOST_ARCH="${HOST_ARCH:-aarch64}"
case "${HOST_ARCH}" in
    aarch64)
        EXPECTED_TRIPLE="aarch64-unknown-linux-musl"
        EXPECTED_MACHINE="AArch64"
        DEFAULT_TOOLCHAIN="$HOME/opt/zig-as-llvm"
        ;;
    x86_64)
        EXPECTED_TRIPLE="x86_64-unknown-linux-musl"
        EXPECTED_MACHINE="Advanced Micro Devices X86-64"
        DEFAULT_TOOLCHAIN="$HOME/opt/zig-as-llvm-x86_64"
        ;;
    armv7)
        EXPECTED_TRIPLE="arm-unknown-linux-musleabihf"
        EXPECTED_MACHINE="ARM"
        DEFAULT_TOOLCHAIN="$HOME/opt/zig-as-llvm-armv7"
        ;;
    *)
        echo "error: unsupported HOST_ARCH '${HOST_ARCH}'" >&2
        exit 2
        ;;
esac

TOOLCHAIN="${TOOLCHAIN:-${DEFAULT_TOOLCHAIN}}"
SYSROOT="${SYSROOT:-$HOME/proj/llvm-toolchain/prebuilts/build-tools/sysroots/${EXPECTED_TRIPLE}}"
CC="${TOOLCHAIN}/bin/cc"
CXX="${TOOLCHAIN}/bin/c++"

for tool in "${CC}" "${CXX}" "${TOOLCHAIN}/bin/ld" "${TOOLCHAIN}/bin/ar" "${TOOLCHAIN}/bin/ranlib" "${TOOLCHAIN}/bin/objcopy" "${TOOLCHAIN}/bin/strip"; do
    [[ -x "${tool}" ]] || { echo "error: missing executable: ${tool}" >&2; exit 3; }
done
[[ -d "${SYSROOT}" ]] || { echo "error: missing sysroot: ${SYSROOT}" >&2; exit 4; }
command -v readelf >/dev/null 2>&1 || { echo "error: readelf is required" >&2; exit 5; }

ACTUAL_TRIPLE="$("${CC}" -dumpmachine)"
case "${ACTUAL_TRIPLE}" in
    "${EXPECTED_TRIPLE}"|"${EXPECTED_TRIPLE}"-*)
        ;;
    *)
        echo "error: compiler target mismatch: expected ${EXPECTED_TRIPLE}, got ${ACTUAL_TRIPLE}" >&2
        exit 6
        ;;
esac

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/smoke.c" <<'C_EOF'
#include <stdio.h>
int main(void) { puts("static-musl-c-ok"); return 0; }
C_EOF

cat > "${TMP_DIR}/smoke.cpp" <<'CPP_EOF'
#include <iostream>
#include <string>
int main() {
    const std::string value = "static-musl-cxx-ok";
    std::cout << value << '\\n';
    return value.empty();
}
CPP_EOF

"${CC}" --sysroot="${SYSROOT}" -static -fPIC "${TMP_DIR}/smoke.c" -o "${TMP_DIR}/smoke-c"
"${CXX}" --sysroot="${SYSROOT}" -static -fPIC -fuse-ld=lld "${TMP_DIR}/smoke.cpp" -o "${TMP_DIR}/smoke-cxx"

for binary in "${TMP_DIR}/smoke-c" "${TMP_DIR}/smoke-cxx"; do
    HEADER="$(readelf -h "${binary}")"
    grep -Fq "Machine:" <<< "${HEADER}" || { echo "error: ELF machine field missing: ${binary}" >&2; exit 7; }
    grep -Fq "${EXPECTED_MACHINE}" <<< "${HEADER}" || {
        echo "error: wrong ELF architecture in ${binary}; expected ${EXPECTED_MACHINE}" >&2
        readelf -h "${binary}" >&2
        exit 8
    }
    if readelf -l "${binary}" | grep -q 'INTERP'; then
        echo "error: ${binary} is dynamically linked; static-musl host tools must not require an ELF interpreter" >&2
        readelf -l "${binary}" >&2
        exit 9
    fi
done

BUILD_MACHINE="$(uname -m)"
case "${BUILD_MACHINE}:${HOST_ARCH}" in
    x86_64:x86_64|aarch64:aarch64|armv7l:armv7|armv8l:armv7)
        "${TMP_DIR}/smoke-c"
        "${TMP_DIR}/smoke-cxx"
        ;;
    *)
        echo "Cross-compiled binaries were inspected but not executed on this build machine."
        ;;
esac

echo "PASS: ${HOST_ARCH} compiler wrapper emits static ${EXPECTED_TRIPLE} C and C++ ELF binaries."
