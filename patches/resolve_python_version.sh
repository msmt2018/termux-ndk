#!/usr/bin/env bash
# Resolve the Linux build-host Python version using the same unique-directory
# discovery rule used by AOSP llvm_android/paths.py.
set -Eeuo pipefail

PYTHON_HOST_ROOT="${PYTHON_HOST_ROOT:-}"
if [[ -z "${PYTHON_HOST_ROOT}" ]]; then
    echo "error: PYTHON_HOST_ROOT must be set before resolving Python" >&2
    return 2
fi

python_include_dirs=("${PYTHON_HOST_ROOT}"/include/python[0-9]*.[0-9]*)
if (( ${#python_include_dirs[@]} != 1 )) || [[ ! -d "${python_include_dirs[0]}" ]]; then
    echo "error: expected exactly one ${PYTHON_HOST_ROOT}/include/pythonX.Y directory" >&2
    printf 'found: %s\n' "${python_include_dirs[@]}" >&2
    return 3
fi

DETECTED_PYTHON_VERSION="${python_include_dirs[0]##*/python}"
if [[ -n "${PYTHON_VERSION:-}" && "${PYTHON_VERSION}" != "${DETECTED_PYTHON_VERSION}" ]]; then
    echo "error: PYTHON_VERSION override (${PYTHON_VERSION}) does not match AOSP prebuilt headers (${DETECTED_PYTHON_VERSION})" >&2
    return 4
fi
PYTHON_VERSION="${DETECTED_PYTHON_VERSION}"

if [[ ! "${PYTHON_VERSION}" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "error: invalid detected Python version: '${PYTHON_VERSION}'" >&2
    return 5
fi

PYTHON_HOST_EXECUTABLE="${PYTHON_HOST_ROOT}/bin/python${PYTHON_VERSION}"
PYTHON_HOST_INCLUDE_DIR="${PYTHON_HOST_ROOT}/include/python${PYTHON_VERSION}"
for required in "${PYTHON_HOST_EXECUTABLE}" "${PYTHON_HOST_INCLUDE_DIR}/Python.h" "${PYTHON_HOST_INCLUDE_DIR}/pyconfig.h"; do
    if [[ ! -e "${required}" ]]; then
        echo "error: incomplete AOSP Python prebuilt; missing ${required}" >&2
        return 6
    fi
done
if [[ ! -x "${PYTHON_HOST_EXECUTABLE}" ]]; then
    echo "error: native Python executable is not executable: ${PYTHON_HOST_EXECUTABLE}" >&2
    return 7
fi

PYTHON_HOST_VERSION_OUTPUT="$("${PYTHON_HOST_EXECUTABLE}" --version 2>&1)" || {
    echo "error: cannot execute native Python: ${PYTHON_HOST_EXECUTABLE}" >&2
    return 8
}
if [[ ! "${PYTHON_HOST_VERSION_OUTPUT}" =~ ^Python[[:space:]]+${PYTHON_VERSION//./\\.}([.][0-9]+)?([[:space:]]|$) ]]; then
    echo "error: Python executable/header version mismatch: expected ${PYTHON_VERSION}, got '${PYTHON_HOST_VERSION_OUTPUT}'" >&2
    return 9
fi

export PYTHON_VERSION PYTHON_HOST_EXECUTABLE PYTHON_HOST_INCLUDE_DIR
