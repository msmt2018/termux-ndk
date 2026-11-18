#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOST_ARCH="${HOST_ARCH:-aarch64}"
LLVM_ROOT="${LLVM_ROOT:-$HOME/proj/llvm-toolchain}"
# shellcheck source=patches/host-env.sh
source "${SCRIPT_DIR}/host-env.sh" "${HOST_ARCH}"

INSTALL_PREFIX="${INSTALL_PREFIX:-${LLVM_ROOT}/out/stage2-install-${HOST_ARCH}}"
case "${HOST_ARCH}" in
    aarch64) EXPECTED_MACHINE="AArch64" ;;
    x86_64) EXPECTED_MACHINE="Advanced Micro Devices X86-64" ;;
    armv7) EXPECTED_MACHINE="ARM" ;;
    *) echo "error: unsupported HOST_ARCH '${HOST_ARCH}'" >&2; exit 2 ;;
esac

[[ -d "${INSTALL_PREFIX}" ]] || { echo "error: stage2 install directory does not exist: ${INSTALL_PREFIX}" >&2; exit 3; }
command -v readelf >/dev/null 2>&1 || { echo "error: readelf is required" >&2; exit 4; }

checked=0
while IFS= read -r -d '' binary; do
    if ! header="$(readelf -h "${binary}" 2>/dev/null)"; then
        continue
    fi

    if ! grep -Fq "${EXPECTED_MACHINE}" <<< "${header}"; then
        echo "error: wrong ELF machine in ${binary}; expected ${EXPECTED_MACHINE}" >&2
        readelf -h "${binary}" >&2
        exit 5
    fi

    if readelf -l "${binary}" 2>/dev/null | grep -q 'INTERP'; then
        echo "error: installed executable has PT_INTERP: ${binary}" >&2
        readelf -l "${binary}" >&2
        exit 6
    fi

    if readelf -d "${binary}" 2>/dev/null | grep -q '(NEEDED)'; then
        echo "error: installed executable has dynamic dependencies: ${binary}" >&2
        readelf -d "${binary}" >&2
        exit 7
    fi

    checked=$((checked + 1))
done < <(find "${INSTALL_PREFIX}" -type f -perm -111 -print0)

if [[ "${checked}" -eq 0 ]]; then
    echo "error: no ELF executables found under ${INSTALL_PREFIX}" >&2
    exit 8
fi

echo "PASS: audited ${checked} static ${EXPECTED_MACHINE} executables in ${INSTALL_PREFIX}."
