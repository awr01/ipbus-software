IPbus software - Cross-compiler fork
====================================

Forked from https://github.com/ipbus/ipbus-software

Overview
--------

This fork prototypes a mechanism for cross-compiling uHAL for ARM aarch64 processors.

Recipe
------

sudo make -f CrossCompile.Makefile PREFIX=/opt/xcompile
sudo make CXX=/opt/xcompile/gcc-arm-10.2-2020.11-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-g++ INCLUDE_PREFIX=/opt/xcompile/include LIB_PREFIX=/opt/xcompile/lib -j$(nproc) Set=uhal NO_UHAL_OPTIONALS=1 install
