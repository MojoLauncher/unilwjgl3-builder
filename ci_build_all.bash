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

echo "Applying patches for LWJGL $LWJGL_VERSION"
apply_patch() {
	echo "Applying patch $1"
   	git apply --reject --whitespace=fix --ignore-whitespace $1 || (echo "git apply failed ($1)" && exit 1)
}

echo "Applying base patches"
for patch in ../patches/uni/*.diff; do
	apply_patch $patch
done

echo "Applying $LWJGL_VERSION patches"
for patch in ../patches/$LWJGL_VERSION/*.diff; do
	apply_patch $patch
done

echo "Applying manual/extra patches"
if [ -f "./modules/lwjgl/core/src/main/c/linux/LinuxLWJGL.h" ]; then
   apply_patch ../patches/manual/lwjgl3_remove_x11_hdr.diff
fi

if [ -f "./modules/lwjgl/core/src/templates/kotlin/core/linux/templates/uio.kt" ]; then
   apply_patch ../patches/manual/lwjgl3_droid_syscall.diff
fi

# Build common jars
export ANTFLAGS="-lib $NASHORN -Dplatform.linux=true -Dbinding.nfd=false -Dbinding.jawt=false -Dbinding.remotery=false -Dbinding.yoga=false -Dbinding.meow=false -Dbinding.rpmalloc=false"
ant $ANTFLAGS compile-templates compile


mkdir debuginfo

for arch in 'arm64' 'arm32' 'x86' 'x64'; do
	if [ -d "../patches/$LWJGL_VERSION/$arch/disable" ]; then
		for d in ../patches/$LWJGL_VERSION/$arch/disable/*; do
			binding=$(basename $d)
			echo "Disabling $binding binding"
			export ANTNATIVEFLAGS="$ANTNATIVEFLAGS -Dbinding.$binding=false"
		done
	fi
	if [[ ! -f ../patches/$LWJGL_VERSION/"$arch"_block ]]; then
		LWJGL_BUILD_ARCH=$arch bash ../ci_build_android.bash
	else echo "Arch $arch is disabled!"
	fi
	export ANTNATIVEFLAGS=$ANTFLAGS
done

yes | ant $ANTFLAGS -Dbuild.offline=true release
