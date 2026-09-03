#!/bin/bash
set -e

if   [ "$LWJGL_BUILD_ARCH" == "arm64" ]; then
  export TOOLCHAIN=arm64 TRIPLET=aarch64-linux-android FFI_SUFFIX=64
elif [ "$LWJGL_BUILD_ARCH" == "arm32" ]; then
  export TOOLCHAIN=arm TRIPLET=arm-linux-androideabi
elif [ "$LWJGL_BUILD_ARCH" == "x86" ]; then
  export TOOLCHAIN=x86 TRIPLET=i686-linux-android
elif [ "$LWJGL_BUILD_ARCH" == "x64" ]; then
  export TOOLCHAIN=x86_64 TRIPLET=x86_64-linux-android FFI_SUFFIX=64
fi

export TOOLCHAIN_PATH=/tmp/toolchain-$TOOLCHAIN

mkdir $TOOLCHAIN_PATH
pushd $TOOLCHAIN_PATH

wget -nc -nv https://github.com/MojoLauncher/gcc-toolchain/releases/download/prebuilt-gcc16/gcc-$TOOLCHAIN-21.tar.xz
tar xf gcc-$TOOLCHAIN-21.tar.xz
rm gcc-$TOOLCHAIN-21.tar.xz

rm sysroot/usr/lib/libstdc++.a
rm sysroot/usr/lib/libstdc++.so

popd

export PATH=$TOOLCHAIN_PATH/bin:$PATH

LWJGL_NATIVE=bin/libs/native/linux/$LWJGL_BUILD_ARCH/org/lwjgl
mkdir -p $LWJGL_NATIVE

if [ "$SKIP_LIBFFI" != "1" ]; then
  export LIBFFI_PREFIX=/tmp/ffi-$TOOLCHAIN

  # Get libffi
  if [ ! -d libffi ]; then
    wget https://github.com/libffi/libffi/releases/download/v$LIBFFI_VERSION/libffi-$LIBFFI_VERSION.tar.gz
    tar xvf libffi-$LIBFFI_VERSION.tar.gz
    mv libffi-$LIBFFI_VERSION libffi
  fi
  pushd libffi

  # Build libffi
  bash configure --host=$TRIPLET --prefix=$LIBFFI_PREFIX
  make -j4
  make install

  popd

  # Copy libffi
  cp $LIBFFI_PREFIX/lib$FFI_SUFFIX/libffi.a $LWJGL_NATIVE/
fi

if [ "$SKIP_DYNCALL" != "1" ]; then
  if [ ! -d dyncall ]; then
     git clone --depth 1 https://github.com/LWJGL-CI/dyncall/
  fi
  pushd dyncall
  mkdir build-$LWJGL_BUILD_ARCH
  pushd build-$LWJGL_BUILD_ARCH

  export DYNCALL_BUILD=$(pwd)

  cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=$TRIPLET-gcc -DCMAKE_CXX_COMPILER=$TRIPLET-g++ -DCMAKE_POLICY_VERSION_MINIMUM=3.5 ..
  cmake --build .

  popd
  popd

  cp $DYNCALL_BUILD/dyncall/libdyncall_s.a $LWJGL_NATIVE/
  cp $DYNCALL_BUILD/dyncallback/libdyncallback_s.a $LWJGL_NATIVE/
  cp $DYNCALL_BUILD/dynload/libdynload_s.a $LWJGL_NATIVE/

fi

export CFLAGS="-D__ANDROID__ -Wno-error -Werror=implicit-function-declaration"
if [ "$LWJGL_BUILD_ARCH" == "arm32" ]; then
   export CFLAGS+=" -march=armv7-a"
fi
ant $ANTNATIVEFLAGS -Dlinux.triplet=$TRIPLET -Dgcc.prefix=$TRIPLET- -Dbuild.offline=true compile-native

#pushd bin
#   echo "Stripping native libs..."
#   find -name "*.so" | xargs -I {} $TRIPLET-objcopy --only-keep-debug {} ../debuginfo/$(basename {}).debug && $TRIPLET-strip {}
#popd
