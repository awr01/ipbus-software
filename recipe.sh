sudo mkdir -m 777 /opt/xcompile
make -f CrossCompile.Makefile PREFIX=/opt/xcompile
make CXX=/opt/xcompile/gcc-arm-10.2-2020.11-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-g++ INCLUDE_PREFIX=/opt/xcompile/include LIB_PREFIX=/opt/xcompile/lib -j8 Set=uhal NO_UHAL_OPTIONALS=1