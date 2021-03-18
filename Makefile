
.NOTPARALLEL:

Set?=all

ifeq ($(Set), uhal)
  PACKAGES = uhal
else ifeq ($(Set), controlhub)
  PACKAGES = controlhub
else ifeq ($(Set), all)
  PACKAGES = uhal controlhub
else
  $(error Invalid value for Set variable!)
endif


BUILD_HOME = $(shell pwd)
include config/Makefile.macros

$(info PACKAGES=$(PACKAGES))


VIRTUAL_PACKAGES = $(addsuffix /.virtual.Makefile,${PACKAGES})

FLAGS = $(ifeq $(MAKEFLAGS) "","",-$(MAKEFLAGS))

TARGETS=all clean build cleanrpm rpm uninstall install

.PHONY: $(TARGETS) 
default: build

$(TARGETS): ${VIRTUAL_PACKAGES}

${VIRTUAL_PACKAGES}:
	${MAKE} ${FLAGS} -C $(@D) $(MAKECMDGOALS)
