#!/bin/bash

make -f CrossCompile.Makefile

make -j8 \
     CXX=$PWD/xcompile/gcc-arm-10.2-2020.11-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-g++ \
     INCLUDE_PREFIX=$PWD/xcompile/include \
     LIB_PREFIX=$PWD/xcompile/lib \
     Set=uhal \
     NO_UHAL_OPTIONALS=1