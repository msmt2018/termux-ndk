#!/usr/bin/env bash
# Resolve the Python version from the pinned AOSP prebuilts instead of
# assuming a particular minor release (AOSP paths.py uses the same discovery
# model: exactly one include/python* directory).
set -Eeuo pipefail

PYTHON_HOST_ROOT="${PYTHON_HOST_ROOT:-}"
if [[ -z "${PYTHON_HOST_ROOT}" ]]; then
    echo "error: PYTHON_HOST_ROOT must be set before resolving Python" >&2
    return 2
fi

if [[ -z "${PYTHON_VERSION:-}" ]]; then
    python_include_dirs=("${PYTHON_HOST_ROOT}"/include/python[0-9]*.[0-9]*)
    if (( ${#python_include_dirs[@]} != 1 )) || [[ ! -d "${python_include_dirs[0]}" ]]; then
        echo "error: expected exactly one ${PYTHON_HOST_ROOT}/include/pythonX.Y directory" >&2
        printf 'found: %s\n' "${python_include_dirs[@]}" >&2
        return 3
    fi
    PYTHON_VERSION="${python_include_dirs[0]##*/python}"
fi

if [[ ! "${PYTHON_VERSION}" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "error: PYTHON_VERSION must have the form X.Y, got '${PYTHON_VERSION}'" >&2
    return 4
fi

PYTHON_HOST_EXECUTABLE="${PYTHON_HOST_ROOT}/bin/python${PYTHON_VERSION}"
if [[ ! -x "${PYTHON_HOST_EXECUTABLE}" ]]; then
    echo "error: missing native Python executable: ${PYTHON_HOST_EXECUTABLE}" >&2
    return 5
fi

export PYTHON_VERSION PYTHON_HOST_EXECUTABLE
