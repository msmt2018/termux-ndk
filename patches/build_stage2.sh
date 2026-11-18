#!/usr/bin/env bash
set -Eeuo pipefail

# Build LLVM stage2 for one Android-runnable CPU architecture using a static
# Linux-musl toolchain. This does NOT produce Bionic-linked Android executables.
#
# Usage:
#   HOST_ARCH=aarch64 bash patches/build_stage2.sh
#   HOST_ARCH=x86_64 TOOLCHAIN="$HOME/opt/zig-as-llvm-x86_64" bash patches/build_stage2.sh
#   HOST_ARCH=armv7 TOOLCHAIN="$HOME/opt/zig-as-llvm-armv7" bash patches/build_stage2.sh
#
# Each HOST_ARCH requires its own Zig wrapper, sysroot and dependency archives.
# Keep the three builds in separate build/install directories.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOST_ARCH="${HOST_ARCH:-aarch64}"
LLVM_ROOT="${LLVM_ROOT:-$HOME/proj/llvm-toolchain}"
# shellcheck source=patches/host-env.sh
source "${SCRIPT_DIR}/host-env.sh" "${HOST_ARCH}"

MUSL_TRIPLE="${TERMUX_NDK_HOST_TRIPLE}"
TOOLCHAIN="${TOOLCHAIN:-${DEFAULT_TOOLCHAIN}}"
LLVM_SRC_DIR="${LLVM_SRC_DIR:-${LLVM_ROOT}/out/llvm-project/llvm}"
BUILD_DIR="${BUILD_DIR:-${LLVM_ROOT}/out/stage2-build-${HOST_ARCH}}"
INSTALL_PREFIX="${INSTALL_PREFIX:-${LLVM_ROOT}/out/stage2-install-${HOST_ARCH}}"
DEPS_PREFIX="${DEPS_PREFIX:-${LLVM_ROOT}/out/lib}"
SYSROOT="${SYSROOT:-${TERMUX_NDK_SYSROOT}}"
TERMUX_NDK_SYSROOT="${SYSROOT}"
export TERMUX_NDK_SYSROOT
PYTHON_HOST_ROOT="${PYTHON_HOST_ROOT:-${LLVM_ROOT}/prebuilts/python/linux-x86}"
PYTHON_TARGET_ROOT="${PYTHON_TARGET_ROOT:-${LLVM_ROOT}/out/python-${MUSL_TRIPLE}-install}"
SWIG_HOST_EXECUTABLE="${SWIG_HOST_EXECUTABLE:-${LLVM_ROOT}/out/host-tools/swig-install/bin/swig}"

# Cross-compilation is determined from the actual build machine, not inferred
# from the output directory name. Zig wrappers must already target HOST_ARCH.
BUILD_MACHINE="$(uname -m)"
case "${BUILD_MACHINE}:${HOST_ARCH}" in
    x86_64:x86_64|aarch64:aarch64|armv7l:armv7|armv8l:armv7)
        CMAKE_CROSSCOMPILING=FALSE
        ;;
    *)
        CMAKE_CROSSCOMPILING=TRUE
        ;;
esac

for tool in cc c++ ld objcopy ar ranlib strip; do
    if [[ ! -x "${TOOLCHAIN}/bin/${tool}" ]]; then
        echo "error: missing executable ${TOOLCHAIN}/bin/${tool}" >&2
        exit 3
    fi
done
for required in "${LLVM_SRC_DIR}/CMakeLists.txt" "${SYSROOT}" "${PYTHON_HOST_ROOT}/bin/python3.12" "${PYTHON_TARGET_ROOT}/lib/libpython3.12.a" "${PYTHON_TARGET_ROOT}/include/python3.12"; do
    if [[ ! -e "${required}" ]]; then
        echo "error: required stage2 input does not exist: ${required}" >&2
        exit 4
    fi
done
[[ -x "${SWIG_HOST_EXECUTABLE}" ]] || { echo "error: missing build-machine-native SWIG executable: ${SWIG_HOST_EXECUTABLE}" >&2; exit 5; }

# Fail before CMake configuration if any architecture-specific static
# dependency has not been built and installed for this exact musl triple.
DEPENDENCY_INPUTS=(
    "${DEPS_PREFIX}/libz-${MUSL_TRIPLE}-install/include"
    "${DEPS_PREFIX}/libz-${MUSL_TRIPLE}-install/lib/libz.a"
    "${DEPS_PREFIX}/libxml2-${MUSL_TRIPLE}-install/include/libxml2"
    "${DEPS_PREFIX}/libxml2-${MUSL_TRIPLE}-install/lib/libxml2.a"
    "${DEPS_PREFIX}/libzstd-${MUSL_TRIPLE}-install/include"
    "${DEPS_PREFIX}/libzstd-${MUSL_TRIPLE}-install/lib/libzstd.a"
    "${DEPS_PREFIX}/liblzma-${MUSL_TRIPLE}-install/include"
    "${DEPS_PREFIX}/liblzma-${MUSL_TRIPLE}-install/lib/liblzma.a"
    "${DEPS_PREFIX}/libedit-${MUSL_TRIPLE}-install/include"
    "${DEPS_PREFIX}/libedit-${MUSL_TRIPLE}-install/lib/libedit.a"
    "${DEPS_PREFIX}/libncurses-${MUSL_TRIPLE}-install/include"
    "${DEPS_PREFIX}/libncurses-${MUSL_TRIPLE}-install/lib/libncurses.a"
    "${DEPS_PREFIX}/libncurses-${MUSL_TRIPLE}-install/lib/libform.a"
    "${DEPS_PREFIX}/libncurses-${MUSL_TRIPLE}-install/lib/libpanel.a"
)
for required in "${DEPENDENCY_INPUTS[@]}"; do
    if [[ ! -e "${required}" ]]; then
        echo "error: missing ${HOST_ARCH} dependency: ${required}" >&2
        exit 5
    fi
done

command -v cmake >/dev/null 2>&1 || { echo "error: cmake is required" >&2; exit 6; }
command -v ninja >/dev/null 2>&1 || { echo "error: ninja is required" >&2; exit 6; }

# Verify the selected wrapper really emits static ELF binaries for this
# architecture; directory names and -dumpmachine alone are not sufficient.
HOST_ARCH="${HOST_ARCH}" TOOLCHAIN="${TOOLCHAIN}" SYSROOT="${SYSROOT}" \
    bash "${SCRIPT_DIR}/validate_host_toolchain.sh"

mkdir -p "${BUILD_DIR}" "${INSTALL_PREFIX}"
cd "${BUILD_DIR}"

echo "Stage2 host architecture : ${HOST_ARCH}"
echo "Musl runtime triple      : ${MUSL_TRIPLE}"
echo "Zig wrapper              : ${TOOLCHAIN}"
echo "Sysroot                  : ${SYSROOT}"
echo "Dependency prefix        : ${DEPS_PREFIX}"
echo "Python host runtime      : ${PYTHON_HOST_ROOT}"
echo "Python target library    : ${PYTHON_TARGET_ROOT}"
echo "Native SWIG executable   : ${SWIG_HOST_EXECUTABLE}"
echo "Build directory          : ${BUILD_DIR}"
echo "Install prefix           : ${INSTALL_PREFIX}"
echo "Cross compiling          : ${CMAKE_CROSSCOMPILING}"

cmake -G Ninja \
    -DCMAKE_C_COMPILER="${TOOLCHAIN}/bin/cc" \
    -DCMAKE_CXX_COMPILER="${TOOLCHAIN}/bin/c++" \
    -DCMAKE_ASM_COMPILER="${TOOLCHAIN}/bin/cc" \
    -DCMAKE_LINKER="${TOOLCHAIN}/bin/ld" \
    -DCMAKE_OBJCOPY="${TOOLCHAIN}/bin/objcopy" \
    -DCMAKE_AR="${TOOLCHAIN}/bin/ar" \
    -DCMAKE_RANLIB="${TOOLCHAIN}/bin/ranlib" \
    -DCMAKE_STRIP="${TOOLCHAIN}/bin/strip" \
    -DCMAKE_C_FLAGS='-static -fPIC -Wno-unused-command-line-argument -Wno-profile-instr-out-of-date -Wno-profile-instr-unprofiled' \
    -DCMAKE_CXX_FLAGS='-static -fPIC -Wno-unused-command-line-argument -Wno-profile-instr-out-of-date -Wno-profile-instr-unprofiled' \
    -DCMAKE_EXE_LINKER_FLAGS='-static -fuse-ld=lld -Wl,--hash-style=both' \
    -DLLVM_TARGETS_TO_BUILD='AArch64;ARM;BPF;RISCV;WebAssembly;X86' \
    -DLLVM_ENABLE_PROJECTS='bolt;clang;clang-tools-extra;lld;lldb;polly' \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_CROSSCOMPILING=${CMAKE_CROSSCOMPILING} \
    -DCMAKE_SYSTEM_PROCESSOR=${CMAKE_PROCESSOR} \
    -DCMAKE_LINK_DEPENDS_USE_LINKER=FALSE \
    -DLLVM_BUILTIN_TARGETS=${MUSL_TRIPLE} \
    -DLLVM_DEFAULT_TARGET_TRIPLE=${MUSL_TRIPLE} \
    -DCLANG_DEFAULT_LINKER=lld \
    -DCLANG_DEFAULT_OBJCOPY=llvm-objcopy \
    -DLLVM_ENABLE_ZLIB=FORCE_ON \
    -DLLVM_ENABLE_ZSTD=FORCE_ON \
    -DLLVM_USE_STATIC_ZSTD=ON \
    -DCLANG_ENABLE_ARCMT=OFF \
    -DLIBCLANG_BUILD_STATIC=ON \
    -DCMAKE_SKIP_INSTALL_RPATH=TRUE \
    -DLLVM_BUILD_STATIC=ON \
    -DLLVM_BUILD_LLVM_DYLIB=OFF \
    -DLLVM_LINK_LLVM_DYLIB=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DLLDB_BUILD_SHARED=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_BUILD_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_BUILD_EXAMPLES=OFF \
    -DLLVM_BUILD_TESTS=OFF \
    -DLLVM_BUILD_TOOLS=ON \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DCLANG_INCLUDE_TESTS=OFF \
    -DCLANG_BUILD_TESTS=OFF \
    -DLLVM_TOOL_C_TEST_BUILD=OFF \
    -DCLANG_TOOL_CLANG_IMPORT_TEST_BUILD=OFF \
    -DCLANG_TOOL_APINOTES_TEST_BUILD=OFF \
    -DCLANG_TOOL_ARCMT_TEST_BUILD=OFF \
    -DCLANG_TOOL_C_ARCMT_TEST_BUILD=OFF \
    -DCLANG_TOOL_C_INDEX_TEST_BUILD=OFF \
    -DLLVM_PARALLEL_LINK_JOBS=4 \
    -DLLVM_ENABLE_PIC=OFF \
    -DLLVM_ENABLE_LIBCXX=OFF \
    -DLLVM_ENABLE_LLVM_LIBC=OFF \
    -DLLVM_ENABLE_UNWIND_TABLES=OFF \
    -DLLVM_ENABLE_EH=OFF \
    -DLLVM_ENABLE_RTTI=OFF \
    -DLLVM_ENABLE_LTO=OFF \
    -DLLVM_ENABLE_TERMINFO=OFF \
    -DLLVM_ENABLE_MODULES=OFF \
    -DLLVM_ENABLE_PEDANTIC=OFF \
    -DLLVM_ENABLE_FFI=OFF \
    -DLLVM_ENABLE_LIBPFM=OFF \
    -DLLVM_ENABLE_LIBEDIT=OFF \
    -DLLVM_ENABLE_LIBXML2=OFF \
    -DLLVM_ENABLE_CURL=OFF \
    -DLLVM_ENABLE_THREADS=ON \
    -DLLVM_VERSION_SUFFIX= \
    -DLLVM_PROFDATA_FILE=$HOME/proj/llvm-toolchain/out/r563880.profdata \
    -DPython3_LIBRARY=${PYTHON_TARGET_ROOT}/lib/libpython3.12.a \
    -DPython3_LIBRARIES=${PYTHON_TARGET_ROOT}/lib/libpython3.12.a \
    -DPython3_INCLUDE_DIR=${PYTHON_TARGET_ROOT}/include/python3.12 \
    -DPython3_INCLUDE_DIRS=${PYTHON_TARGET_ROOT}/include/python3.12 \
    -DPython3_EXECUTABLE=${PYTHON_HOST_ROOT}/bin/python3.12 \
    -DZLIB_INCLUDE_DIR=${DEPS_PREFIX}/libz-${MUSL_TRIPLE}-install/include \
    -DZLIB_LIBRARY=${DEPS_PREFIX}/libz-${MUSL_TRIPLE}-install/lib/libz.a \
    -DLIBXML2_INCLUDE_DIR=${DEPS_PREFIX}/libxml2-${MUSL_TRIPLE}-install/include/libxml2 \
    -DLIBXML2_LIBRARY=${DEPS_PREFIX}/libxml2-${MUSL_TRIPLE}-install/lib/libxml2.a \
    -Dzstd_LIBRARY=${DEPS_PREFIX}/libzstd-${MUSL_TRIPLE}-install/lib/libzstd.a \
    -Dzstd_INCLUDE_DIR=${DEPS_PREFIX}/libzstd-${MUSL_TRIPLE}-install/include \
    -DLLDB_ENABLE_LUA=OFF \
    -DSWIG_EXECUTABLE=${SWIG_HOST_EXECUTABLE} \
    -DLLDB_ENABLE_PYTHON=ON \
    -DLLDB_EMBED_PYTHON_HOME=OFF \
    -DLLDB_ENABLE_LZMA=ON \
    -DLLVM_ENABLE_LZMA=FORCE_ON \
    -DLLVM_USE_STATIC_LZMA=ON \
    -DLIBLZMA_INCLUDE_DIR=${DEPS_PREFIX}/liblzma-${MUSL_TRIPLE}-install/include \
    -DLIBLZMA_LIBRARY=${DEPS_PREFIX}/liblzma-${MUSL_TRIPLE}-install/lib/liblzma.a \
    -DLLDB_ENABLE_LIBEDIT=ON \
    -DLibEdit_INCLUDE_DIRS=${DEPS_PREFIX}/libedit-${MUSL_TRIPLE}-install/include \
    -DLibEdit_LIBRARIES=${DEPS_PREFIX}/libedit-${MUSL_TRIPLE}-install/lib/libedit.a \
    -DLLDB_ENABLE_LIBXML2=ON \
    -DLLDB_ENABLE_CURSES=ON \
    -DLLDB_INCLUDE_TESTS=OFF \
    -DCURSES_INCLUDE_DIRS="${DEPS_PREFIX}/libncurses-${MUSL_TRIPLE}-install/include;${DEPS_PREFIX}/libncurses-${MUSL_TRIPLE}-install/include/ncurses" \
    -DCURSES_LIBRARIES="${DEPS_PREFIX}/libncurses-${MUSL_TRIPLE}-install/lib/libncurses.a;${DEPS_PREFIX}/libncurses-${MUSL_TRIPLE}-install/lib/libform.a;${DEPS_PREFIX}/libncurses-${MUSL_TRIPLE}-install/lib/libpanel.a" \
    -DPANEL_LIBRARIES="${DEPS_PREFIX}/libncurses-${MUSL_TRIPLE}-install/lib/libncurses.a;${DEPS_PREFIX}/libncurses-${MUSL_TRIPLE}-install/lib/libform.a;${DEPS_PREFIX}/libncurses-${MUSL_TRIPLE}-install/lib/libpanel.a" \
    -DCLANG_VENDOR='Android (dev, +pgo, -bolt, +lto, -mlgo, based on r563880c)' \
    -DCLANG_REPOSITORY_STRING='https://android.googlesource.com/toolchain/llvm-project' \
    -DBUG_REPORT_URL='https://github.com/android-ndk/ndk/issues' \
    '-DLLVM_ENABLE_RUNTIMES=compiler-rt;libcxx;libcxxabi;libunwind' \
    "-DLLVM_RUNTIME_TARGETS=${MUSL_TRIPLE}" \
    -DCMAKE_SYSROOT=${SYSROOT} \
    -DLLVM_BUILD_RUNTIME=ON \
    -DLIBCXX_ENABLE_STATIC=ON \
    -DLIBCXX_ENABLE_SHARED=OFF \
    -DLIBCXXABI_ENABLE_STATIC=ON \
    -DLIBCXXABI_ENABLE_SHARED=OFF \
    -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
    -DCOMPILER_SUPPORTS_UNWIND_TABLES=ON \
    -DLIBUNWIND_ENABLE_STATIC=ON \
    -DLIBUNWIND_ENABLE_SHARED=OFF \
    -DCOMPILER_RT_BUILD_LIBFUZZER=ON \
    -DLIBCXX_USE_COMPILER_RT=TRUE \
    -DLIBCXX_HAS_MUSL_LIBC=TRUE \
    -DLIBCXXABI_USE_COMPILER_RT=TRUE \
    -DLIBUNWIND_USE_COMPILER_RT=TRUE \
    -DCOMPILER_RT_USE_BUILTINS_LIBRARY=TRUE \
    -DLIBCXX_HAS_RT_LIB=FALSE \
    -DLIBCXX_HAS_PTHREAD_LIB=FALSE \
    -DLIBCXXABI_HAS_PTHREAD_LIB=FALSE \
    -DLIBUNWIND_HAS_DL_LIB=FALSE \
    -DLIBUNWIND_HAS_PTHREAD_LIB=FALSE \
    -DRUNTIMES_${MUSL_TRIPLE}_LIBCXX_INCLUDE_BENCHMARKS=OFF \
    "-DBUILTINS_${MUSL_TRIPLE}_CMAKE_C_FLAGS=-static -fPIC -D_LIBCPP_HAS_MUSL_LIBC -D_LARGEFILE64_SOURCE=1 -D_LIBCPP_AVAILABILITY_HAS_NO_VERBOSE_ABORT=1 -Wno-profile-instr-out-of-date -Wno-profile-instr-unprofiled" \
    "-DBUILTINS_${MUSL_TRIPLE}_CMAKE_CXX_FLAGS=-static -fPIC -D_LIBCPP_HAS_MUSL_LIBC -D_LARGEFILE64_SOURCE=1 -Wno-unused-command-line-argument -D_LIBCPP_AVAILABILITY_HAS_NO_VERBOSE_ABORT=1 -Wno-profile-instr-out-of-date -Wno-profile-instr-unprofiled" \
    "-DBUILTINS_${MUSL_TRIPLE}_CMAKE_EXE_LINKER_FLAGS=-static -fuse-ld=lld -Wl,--hash-style=both" \
    "-DBUILTINS_${MUSL_TRIPLE}_CMAKE_SHARED_LINKER_FLAGS=-static -fuse-ld=lld -Wl,--hash-style=both" \
    "-DBUILTINS_${MUSL_TRIPLE}_CMAKE_MODULE_LINKER_FLAGS=-static -fuse-ld=lld -Wl,--hash-style=both" \
    -DRUNTIMES_${MUSL_TRIPLE}_CMAKE_SYSROOT=${SYSROOT} \
    -DBUILTINS_${MUSL_TRIPLE}_CMAKE_PLATFORM_NO_VERSIONED_SONAME=ON \
    -DBUILTINS_${MUSL_TRIPLE}_LIBCXX_USE_COMPILER_RT=TRUE \
    -DBUILTINS_${MUSL_TRIPLE}_LIBCXX_HAS_MUSL_LIBC=TRUE \
    -DBUILTINS_${MUSL_TRIPLE}_LIBCXXABI_USE_COMPILER_RT=TRUE \
    -DBUILTINS_${MUSL_TRIPLE}_LIBUNWIND_USE_COMPILER_RT=TRUE \
    -DBUILTINS_${MUSL_TRIPLE}_COMPILER_RT_USE_BUILTINS_LIBRARY=TRUE \
    -DBUILTINS_${MUSL_TRIPLE}_CMAKE_LINK_DEPENDS_USE_LINKER=FALSE \
    -DBUILTINS_${MUSL_TRIPLE}_LIBCXX_HAS_RT_LIB=FALSE \
    -DBUILTINS_${MUSL_TRIPLE}_LIBCXX_HAS_PTHREAD_LIB=FALSE \
    -DBUILTINS_${MUSL_TRIPLE}_LIBCXXABI_HAS_PTHREAD_LIB=FALSE \
    -DBUILTINS_${MUSL_TRIPLE}_LIBUNWIND_HAS_DL_LIB=FALSE \
    -DBUILTINS_${MUSL_TRIPLE}_LIBUNWIND_HAS_PTHREAD_LIB=FALSE \
    -DBUILTINS_${MUSL_TRIPLE}_LLVM_DEFAULT_TARGET_TRIPLE=${MUSL_TRIPLE} \
    -DBUILTINS_${MUSL_TRIPLE}_CMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILTINS_${MUSL_TRIPLE}_LLVM_ENABLE_LIBCXX=ON \
    -DBUILTINS_${MUSL_TRIPLE}_LIBCXXABI_USE_LLVM_UNWINDER=ON \
    -DBUILTINS_${MUSL_TRIPLE}_LIBCXXABI_ENABLE_STATIC_UNWINDER=ON \
    -DBUILTINS_${MUSL_TRIPLE}_LIBCXX_HAS_ATOMIC_LIB=NO \
    -DBUILTINS_${MUSL_TRIPLE}_LIBCXX_ENABLE_ABI_LINKER_SCRIPT=OFF \
    -DBUILTINS_${MUSL_TRIPLE}_LIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
    "-DBUILTINS_${MUSL_TRIPLE}_LIBCXX_TEST_COMPILER_FLAGS=-static -fPIC -D_LIBCPP_HAS_MUSL_LIBC -D_LARGEFILE64_SOURCE=1 -Wno-unused-command-line-argument -D_LIBCPP_AVAILABILITY_HAS_NO_VERBOSE_ABORT=1 -Wno-profile-instr-out-of-date -Wno-profile-instr-unprofiled" \
    "-DBUILTINS_${MUSL_TRIPLE}_LIBCXX_TEST_LINKER_FLAGS=-static -fuse-ld=lld -Wl,--hash-style=both" \
    -DBUILTINS_${MUSL_TRIPLE}_SANITIZER_ALLOW_CXXABI=OFF \
    "-DRUNTIMES_${MUSL_TRIPLE}_CMAKE_C_FLAGS=-static -fPIC -D_LIBCPP_HAS_MUSL_LIBC -D_LARGEFILE64_SOURCE=1 -D_LIBCPP_AVAILABILITY_HAS_NO_VERBOSE_ABORT=1 -Wno-profile-instr-out-of-date -Wno-profile-instr-unprofiled" \
    "-DRUNTIMES_${MUSL_TRIPLE}_CMAKE_CXX_FLAGS=-static -fPIC -D_LIBCPP_HAS_MUSL_LIBC -D_LARGEFILE64_SOURCE=1 -Wno-unused-command-line-argument -D_LIBCPP_AVAILABILITY_HAS_NO_VERBOSE_ABORT=1 -Wno-profile-instr-out-of-date -Wno-profile-instr-unprofiled" \
    "-DRUNTIMES_${MUSL_TRIPLE}_CMAKE_EXE_LINKER_FLAGS=-static -fuse-ld=lld -Wl,--hash-style=both" \
    "-DRUNTIMES_${MUSL_TRIPLE}_CMAKE_SHARED_LINKER_FLAGS=-static -fuse-ld=lld -Wl,--hash-style=both" \
    "-DRUNTIMES_${MUSL_TRIPLE}_CMAKE_MODULE_LINKER_FLAGS=-static -fuse-ld=lld -Wl,--hash-style=both" \
    -DRUNTIMES_${MUSL_TRIPLE}_CMAKE_PLATFORM_NO_VERSIONED_SONAME=ON \
    -DRUNTIMES_${MUSL_TRIPLE}_LIBCXX_USE_COMPILER_RT=TRUE \
    -DRUNTIMES_${MUSL_TRIPLE}_LIBCXX_HAS_MUSL_LIBC=TRUE \
    -DRUNTIMES_${MUSL_TRIPLE}_LIBCXXABI_USE_COMPILER_RT=TRUE \
    -DRUNTIMES_${MUSL_TRIPLE}_LIBUNWIND_USE_COMPILER_RT=TRUE \
    -DRUNTIMES_${MUSL_TRIPLE}_COMPILER_RT_USE_BUILTINS_LIBRARY=TRUE \
    -DRUNTIMES_${MUSL_TRIPLE}_CMAKE_LINK_DEPENDS_USE=FALSE \
    ${LLVM_SRC_DIR}
