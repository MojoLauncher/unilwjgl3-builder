#!/bin/bash

set -e

if [ -z "$LWJGL_VERSION" ]; then
   echo "LWJGL version not set"
   exit 1
fi

if [ -z "$LIBFFI_VERSION" ]; then
   echo "libffi version not set"
   exit 1
fi

if [[ "$LWJGL_VERSION" == "3.2.3" ]]; then
   export SKIP_LIBFFI=1
else
   export SKIP_DYNCALL=1
fi

mkdir lib
pushd lib
wget -nc -nv https://repo1.maven.org/maven2/org/openjdk/nashorn/nashorn-core/15.7/nashorn-core-15.7.jar
wget -nc -nv https://repo1.maven.org/maven2/org/ow2/asm/asm/7.3.1/asm-7.3.1.jar
wget -nc -nv https://repo1.maven.org/maven2/org/ow2/asm/asm-commons/7.3.1/asm-commons-7.3.1.jar
wget -nc -nv https://repo1.maven.org/maven2/org/ow2/asm/asm-tree/7.3.1/asm-tree-7.3.1.jar
wget -nc -nv https://repo1.maven.org/maven2/org/ow2/asm/asm-util/7.3.1/asm-util-7.3.1.jar
export NASHORN=$(pwd)
popd

git clone --depth 1 --branch $LWJGL_VERSION https://github.com/LWJGL/lwjgl3
cd lwjgl3

apply_patch() {
   git apply --reject --whitespace=fix --ignore-whitespace ../$1.diff || (echo "git apply failed ($2)" && exit 1)
}

apply_patch lwjgl3_uni_cflags_ldflags "CFLAGS/LDFLAGS support"
apply_patch lwjgl3_uni_x86_jar "create native JARs for x86"
apply_patch lwjgl3_uni_arm_float_workaround "workaround for MemoryUtil floats and doubles on ARM"

if [[ "$LWJGL_VERSION" == "3.4.1" ]]; then
	apply_patch lwjgl3_3.4.1_exclude_gl30_check "Use unavailable functions in the current context (3.4.1)"
fi

if [[ "$LWJGL_VERSION" != "3.4.1" && "$LWJGL_VERSION" != "3.2.3" ]]; then
	apply_patch lwjgl3_3.3.6_exclude_gl30_check "Use unavailable functions in the current context (3.3.6>)"
fi

if [ -f "./modules/lwjgl/core/src/templates/kotlin/core/linux/templates/uio.kt" ]; then
   apply_patch lwjgl3_droid_syscall "UIO system call support"
fi

if [ -f "./modules/lwjgl/core/src/main/c/linux/LinuxLWJGL.h" ]; then
   apply_patch lwjgl3_remove_x11_hdr "remove unused X11 headers"
fi

if [[ "$LWJGL_VERSION" == "3.3.1" ]]; then
   apply_patch lwjgl3_3.3.1_xxhash_static_assert "fix static assert macro in xxHash"
   apply_patch lwjgl3_3.3.1_uring_type "add missing type into ui_uring.h"
fi

if [[ "$LWJGL_VERSION" == "3.2.3" || "$LWJGL_VERSION" == "3.3.1" ]]; then
   apply_patch lwjgl3_3.2.3_use_packaging_arch "fix offline build natives arch"
   apply_patch lwjgl3_3.3.1_replace_locale-sensitive_string_format "fix crash on arabic locale by replacing locale-sensitive String.format"
fi

if [[ "$LWJGL_VERSION" == "3.2.3" ]]; then
   apply_patch lwjgl3_3.2.3_rpmalloc_madvise "use linux madvise instead of posix_madvise when available"
fi

export ANTFLAGS="-lib $NASHORN -Dplatform.linux=true -Dbinding.nfd=false -Dbinding.jawt=false -Dbinding.remotery=false -Dbinding.zstd=false -Dbinding.yoga=false -Dbinding.meow=false"

ant $ANTFLAGS compile-templates compile

mkdir debuginfo

LWJGL_BUILD_ARCH=arm64 bash ../ci_build_android.bash
LWJGL_BUILD_ARCH=arm32 bash ../ci_build_android.bash
LWJGL_BUILD_ARCH=x86 bash ../ci_build_android.bash
LWJGL_BUILD_ARCH=x64 bash ../ci_build_android.bash

yes | ant $ANTFLAGS -Dbuild.offline=true release
