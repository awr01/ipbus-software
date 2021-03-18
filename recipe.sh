#!/bin/bash

if [ $(whoami) != 'root' ]; then
  echo "You must be root to do this."
  exit 1
fi

make -f CrossCompile.Makefile \
     PREFIX=/opt/xcompile

make -j8 \
     CXX=/opt/xcompile/gcc-arm-10.2-2020.11-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-g++ \
     INCLUDE_PREFIX=/opt/xcompile/include \
     LIB_PREFIX=/opt/xcompile/lib \
     Set=uhal \
     NO_UHAL_OPTIONALS=1 \
     install