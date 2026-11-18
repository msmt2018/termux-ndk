#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=patches/upstream-revisions.lock
source "${SCRIPT_DIR}/upstream-revisions.lock"

LLVM_ROOT="${LLVM_ROOT:-$PWD/llvm-toolchain}"
SOURCE_ROOT="${SOURCE_ROOT:-${LLVM_ROOT}/src}"
mkdir -p "${SOURCE_ROOT}"

checkout_exact() {
    local name="$1" url="$2" revision="$3" destination="${SOURCE_ROOT}/$1"

    if [[ -e "${destination}" && ! -d "${destination}/.git" ]]; then
        echo "error: refusing to overwrite non-git source path: ${destination}" >&2
        return 20
    fi

    if [[ ! -d "${destination}/.git" ]]; then
        mkdir -p "${destination}"
        git -C "${destination}" init
        git -C "${destination}" remote add origin "${url}"
    else
        local current_url
        current_url="$(git -C "${destination}" remote get-url origin)"
        if [[ "${current_url}" != "${url}" ]]; then
            echo "error: ${name} origin mismatch: ${current_url}" >&2
            return 21
        fi
    fi

    git -C "${destination}" fetch --no-tags --depth=1 origin "${revision}"
    git -C "${destination}" checkout --detach FETCH_HEAD

    local actual
    actual="$(git -C "${destination}" rev-parse HEAD)"
    if [[ "${actual}" != "${revision}" ]]; then
        echo "error: ${name} revision mismatch: expected ${revision}, got ${actual}" >&2
        return 22
    fi
    printf 'PINNED %s %s\n' "${name}" "${actual}"
}

checkout_exact llvm-project "${LLVM_PROJECT_URL}" "${LLVM_PROJECT_REVISION}"
checkout_exact llvm_android "${LLVM_ANDROID_URL}" "${LLVM_ANDROID_REVISION}"
checkout_exact ndk "${NDK_URL}" "${NDK_REVISION}"

printf 'Source checkouts are pinned to %s.\n' "${CLANG_RELEASE}"
