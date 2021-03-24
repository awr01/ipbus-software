PREFIX ?= $(shell pwd)/xcompile

WORKING_DIR ?= $(shell pwd)/.xcompile

COMPILER_VERSION = 10.2-2020.11
CXX = ${PREFIX}/gcc-arm-${COMPILER_VERSION}-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-g++

DIRECTORIES = ${WORKING_DIR} ${PREFIX} ${PREFIX}/include ${PREFIX}/lib



.PHONY: all _all clean _cleanall build _buildall # install _installall rpm _rpmall test _testall

default: build

clean: _cleanall
_cleanall:
	rm -rf ${DIRECTORIES}

all: _all
build: _all
buildall: _all

_all: ${CXX} libs

# ----------------------------------------------------------------------------------------------
${DIRECTORIES}:
	mkdir -p $@
# ----------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------
${WORKING_DIR}/gcc-arm-${COMPILER_VERSION}-x86_64-aarch64-none-linux-gnu.tar.xz : | ${WORKING_DIR}
	wget -nc -t0 -P ${WORKING_DIR} https://developer.arm.com/-/media/Files/downloads/gnu-a/${COMPILER_VERSION}/binrel/$$(basename $@)

${CXX} : ${WORKING_DIR}/gcc-arm-${COMPILER_VERSION}-x86_64-aarch64-none-linux-gnu.tar.xz | ${PREFIX}
	tar -C ${PREFIX} -xmJf $<
# ----------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------
/etc/yum.repos.d/aarch64.repo:
	sudo echo -e "[arm]\nname=arm\nbaseurl=http://linuxsoft.cern.ch/centos-altarch/7/os/aarch64/\n\n[arm-epel]\nname=arm-epel\nbaseurl=http://linuxsoft.cern.ch/epel/7/aarch64/" > /etc/yum.repos.d/aarch64.repo
	sudo yum makecache

${WORKING_DIR}/zlib-1.2.7-18.el7.aarch64.rpm : /etc/yum.repos.d/aarch64.repo | ${WORKING_DIR}
	repotrack -a aarch64 -p ${WORKING_DIR} boost169 boost169-devel pugixml pugixml-devel

${PREFIX}/lib/usr/lib64/libz.so.1 : ${WORKING_DIR}/zlib-1.2.7-18.el7.aarch64.rpm | ${PREFIX}/include ${PREFIX}/lib
	cd ${PREFIX}/include ; for i in $$(find ${WORKING_DIR} -iname "*.rpm"); do rpm2cpio $${i} | cpio --quiet -idu *.h *.hpp *.ipp ; done
	cd ${PREFIX}/lib ; for i in $$(find ${WORKING_DIR} -iname "*.rpm"); do rpm2cpio $${i} | cpio --quiet -idu *.so *.so.* ; done

libs : ${PREFIX}/lib/usr/lib64/libz.so.1
# ----------------------------------------------------------------------------------------------

