#!/usr/bin/env bash
set -Eeuo pipefail

# Build native TableGen executables for use by cross-compiled Stage2 builds.
# These tools run on the build machine; they must not be compiled for HOST_ARCH.
#
# Usage:
#   bash patches/build_native_tools.sh

LLVM_ROOT="${LLVM_ROOT:-$HOME/proj/llvm-toolchain}"
LLVM_SRC_DIR="${LLVM_SRC_DIR:-${LLVM_ROOT}/out/llvm-project/llvm}"
NATIVE_BUILD_DIR="${NATIVE_BUILD_DIR:-${LLVM_ROOT}/out/native-tools-build}"
DEFAULT_JOBS=2
if command -v nproc >/dev/null 2>&1; then DEFAULT_JOBS="$(nproc)"; fi
BUILD_JOBS="${BUILD_JOBS:-${DEFAULT_JOBS}}"

[[ -f "${LLVM_SRC_DIR}/CMakeLists.txt" ]] || {
    echo "error: LLVM source tree not found: ${LLVM_SRC_DIR}" >&2
    exit 2
}
command -v cmake >/dev/null 2>&1 || { echo "error: cmake is required" >&2; exit 3; }
command -v ninja >/dev/null 2>&1 || { echo "error: ninja is required" >&2; exit 3; }
command -v "${HOST_CC:-cc}" >/dev/null 2>&1 || { echo "error: native C compiler is required" >&2; exit 3; }
command -v "${HOST_CXX:-c++}" >/dev/null 2>&1 || { echo "error: native C++ compiler is required" >&2; exit 3; }
[[ "${BUILD_JOBS}" =~ ^[1-9][0-9]*$ ]] || { echo "error: BUILD_JOBS must be a positive integer" >&2; exit 4; }

mkdir -p "${NATIVE_BUILD_DIR}"

cmake -G Ninja \
    -S "${LLVM_SRC_DIR}" \
    -B "${NATIVE_BUILD_DIR}" \
    -DCMAKE_C_COMPILER="${HOST_CC:-cc}" \
    -DCMAKE_CXX_COMPILER="${HOST_CXX:-c++}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${NATIVE_BUILD_DIR}/install" \
    -DLLVM_ENABLE_PROJECTS='clang;lldb' \
    -DLLVM_TARGETS_TO_BUILD='AArch64;ARM;X86' \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_ENABLE_TERMINFO=OFF \
    -DLLVM_ENABLE_LIBEDIT=OFF \
    -DLLVM_ENABLE_ZLIB=OFF \
    -DLLVM_ENABLE_ZSTD=OFF \
    -DLLVM_ENABLE_LIBXML2=OFF \
    -DLLVM_ENABLE_FFI=OFF \
    -DLLDB_ENABLE_PYTHON=OFF \
    -DLLDB_ENABLE_LIBEDIT=OFF \
    -DLLDB_ENABLE_CURSES=OFF \
    -DLLDB_ENABLE_LIBXML2=OFF

cmake --build "${NATIVE_BUILD_DIR}" \
    --target llvm-tblgen clang-tblgen lldb-tblgen \
    --parallel "${BUILD_JOBS}"

for tool in llvm-tblgen clang-tblgen lldb-tblgen; do
    binary="${NATIVE_BUILD_DIR}/bin/${tool}"
    [[ -x "${binary}" ]] || {
        echo "error: native TableGen tool was not produced: ${binary}" >&2
        exit 5
    }
    "${binary}" --version >/dev/null
done

echo "PASS: native TableGen tools are ready in ${NATIVE_BUILD_DIR}/bin"
