PREFIX ?= $(shell pwd)

WORKING_DIR = cross-compile

COMPILER_VERSION = 10.2-2020.11
CXX = ${PREFIX}/gcc-arm-${COMPILER_VERSION}-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-g++

BOOST_MAJOR = 1
BOOST_MINOR = 75
BOOST_PATCH = 0
BOOST = boost_${BOOST_MAJOR}_${BOOST_MINOR}_${BOOST_PATCH}

PUGIXML_MAJOR = 1
PUGIXML_MINOR = 11
PUGIXML_PATCH = 4
PUGIXML = pugixml

DIRECTORIES = ${WORKING_DIR} ${PREFIX}/include ${PREFIX}/lib



.PHONY: all _all clean _cleanall build _buildall # install _installall rpm _rpmall test _testall

default: build

clean: _cleanall
_cleanall:
	rm -rf ${DIRECTORIES}

all: _all
build: _all
buildall: _all

_all: ${CXX} pugixml_library boost_library

# ----------------------------------------------------------------------------------------------
${DIRECTORIES}:
	mkdir -p $@
# ----------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------
${WORKING_DIR}/gcc-arm-${COMPILER_VERSION}-x86_64-aarch64-none-linux-gnu.tar.xz : | ${WORKING_DIR}
	wget -nc -t0 -P ${WORKING_DIR} https://developer.arm.com/-/media/Files/downloads/gnu-a/${COMPILER_VERSION}/binrel/gcc-arm-${COMPILER_VERSION}-x86_64-aarch64-none-linux-gnu.tar.xz

${CXX} : ${WORKING_DIR}/gcc-arm-${COMPILER_VERSION}-x86_64-aarch64-none-linux-gnu.tar.xz
	tar -C ${PREFIX} -xmJf $<
# ----------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------
${WORKING_DIR}/${PUGIXML} : | ${WORKING_DIR}
	git config --global advice.detachedHead false
	git clone --depth 1 -b v${PUGIXML_MAJOR}.${PUGIXML_MINOR}.${PUGIXML_PATCH} https://github.com/zeux/pugixml.git $@

${PREFIX}/lib/libpugixml.so : ${WORKING_DIR}/${PUGIXML} ${CXX} | ${PREFIX}/include ${PREFIX}/lib
	cp $</src/*.hpp ${PREFIX}/include
	${CXX} -fPIC -O3 -shared -o $@ $</src/pugixml.cpp

pugixml_library : ${PREFIX}/lib/libpugixml.so
# ----------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------
${WORKING_DIR}/${BOOST}.tar.gz : | ${WORKING_DIR}
	wget -nc -t0 -P ${WORKING_DIR} https://dl.bintray.com/boostorg/release/${BOOST_MAJOR}.${BOOST_MINOR}.${BOOST_PATCH}/source/${BOOST}.tar.gz

${WORKING_DIR}/${BOOST} : ${WORKING_DIR}/${BOOST}.tar.gz
	tar -C ${WORKING_DIR} -xzf $<

${WORKING_DIR}/${BOOST}/project-config.jam : ${WORKING_DIR}/${BOOST}
	cd $< ; ./bootstrap.sh --prefix=${PREFIX} ;
	sed -i "s|using gcc ;|using gcc : arm : ${CXX} ;|g" $@

${PREFIX}/boost/lib/libboost_wserialization.so : ${WORKING_DIR}/${BOOST}/project-config.jam ${CXX}
	cd ${WORKING_DIR}/${BOOST}; ./b2 install toolset=gcc-arm link=shared runtime-link=shared -prefix=${PREFIX}

boost_library : ${PREFIX}/boost/lib/libboost_wserialization.so
# ----------------------------------------------------------------------------------------------

