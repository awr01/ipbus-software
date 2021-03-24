#!/bin/bash
set -x #echo on
set -e #exit on error

make -f CrossCompile.Makefile

make -j8 \
     CXX=$PWD/xcompile/gcc-arm-10.2-2020.11-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-g++ \
     INCLUDE_PREFIX="$PWD/xcompile/include/usr/include $PWD/xcompile/include/usr/include/boost169" \
     LIB_PREFIX="$PWD/xcompile/lib/usr/lib64 $PWD/xcompile/lib/usr/lib64/boost169" \
     Set=uhal \
     NO_UHAL_OPTIONALS=1