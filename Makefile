SHELL = /bin/bash
-include make.conf
OBJS := parser.o main.o redsocks.o log.o http-connect.o socks4.o socks5.o http-relay.o base.o base64.o md5.o http-auth.o utils.o redudp.o dnstc.o dnsu2t.o gen/version.o
ifeq ($(DBG_BUILD),1)
OBJS += debug.o
endif
SRCS := $(OBJS:.o=.c)
CONF := config.h
DEPS := .depend
OUT := redsocks
VERSION := 0.5
OS := $(shell uname)

LIBS := -levent_core
ifeq ($(DBG_BUILD),1)
# -levent_extra is required only for `http` and `debug`
LIBS += -levent_extra
endif
# CFLAGS += -g -O2
# # _GNU_SOURCE is used to get splice(2), it also implies _BSD_SOURCE
# override CFLAGS += -std=c99 -D_XOPEN_SOURCE=600 -D_DEFAULT_SOURCE -D_GNU_SOURCE -Wall
CFLAGS +=-fPIC -O3
ifeq ($(OS), Darwin)
override CFLAGS += -D_DARWIN_C_SOURCE -D_DEFAULT_SOURCE -Wall
else
override CFLAGS +=  -D_GNU_SOURCE -D_DEFAULT_SOURCE -Wall
ifeq ($(OS), Linux)
override CFLAGS += -std=c99 -D_XOPEN_SOURCE=600
endif
endif
ifeq ($(OS), Darwin)
# override CFLAGS +=-I/usr/local/opt/openssl/include -L/usr/local/opt/openssl/lib
# override CFLAGS +=-I/opt/local/include/openssl -L/opt/local/lib
SHELL := /bin/bash
# OSX_VERSION := $(shell sw_vers -productVersion | cut -d '.' -f 1,2)
OSX_VERSION := master
OSX_ROOT_PATH := xnu
OSX_HEADERS_PATH := $(OSX_ROOT_PATH)/$(OSX_VERSION)
OSX_HEADERS := $(OSX_HEADERS_PATH)/net/pfvar.h $(OSX_HEADERS_PATH)/net/radix.h $(OSX_HEADERS_PATH)/libkern/tree.h
override CFLAGS += -I$(OSX_HEADERS_PATH)
endif

all: $(OUT)

.PHONY: all clean distclean test

tags: *.c *.h
	ctags -R

$(CONF):
	@case `uname` in \
	Linux*) \
		echo "#define USE_IPTABLES" >$(CONF) \
		;; \
	OpenBSD) \
		echo "#define USE_PF" >$(CONF) \
		;; \
	Darwin) \
		echo -e "#define USE_PF\n#define _APPLE_" >$(CONF) \
		;; \
	*) \
		echo "Unknown system, only generic firewall code is compiled" 1>&2; \
		echo "/* Unknown system, only generic firewall code is compiled */" >$(CONF) \
		;; \
	esac
ifeq ($(DBG_BUILD),1)
	echo "#define DBG_BUILD 1" >>$(CONF)
endif

# Dependency on .git is useful to rebuild `version.c' after commit, but it breaks non-git builds.
gen/version.c: *.c *.h gen/.build
	rm -f $@.tmp
	echo '/* this file is auto-generated during build */' > $@.tmp
	echo '#include "../version.h"' >> $@.tmp
	echo 'const char* redsocks_version = ' >> $@.tmp
	if [ -d .git ]; then \
		echo '"redsocks.git/'`git describe --tags`'"'; \
		if [ `git status --porcelain | grep -v -c '^??'` != 0 ]; then \
			echo '"'"-unclean-$$(date --rfc-3339=seconds | tr ' ' 'T')-$${USER}@$$(uname -n)"'"'; \
		fi \
	else \
		echo '"redsocks/$(VERSION)"'; \
	fi >> $@.tmp
	echo ';' >> $@.tmp
	mv -f $@.tmp $@

gen/.build:
	mkdir -p gen
	touch $@

base.c: $(CONF)
	

ifeq ($(OS), Darwin)
$(OSX_HEADERS_PATH)/net/pfvar.h:
	mkdir -p $(OSX_HEADERS_PATH)/net && curl -o $(OSX_HEADERS_PATH)/net/pfvar.h https://raw.githubusercontent.com/opensource-apple/xnu/$(OSX_VERSION)/bsd/net/pfvar.h
$(OSX_HEADERS_PATH)/net/radix.h:
	mkdir -p $(OSX_HEADERS_PATH)/net && curl -o $(OSX_HEADERS_PATH)/net/radix.h https://raw.githubusercontent.com/opensource-apple/xnu/$(OSX_VERSION)/bsd/net/radix.h
$(OSX_HEADERS_PATH)/libkern/tree.h:
	mkdir -p $(OSX_HEADERS_PATH)/libkern && curl -o $(OSX_HEADERS_PATH)/libkern/tree.h https://raw.githubusercontent.com/opensource-apple/xnu/$(OSX_VERSION)/libkern/libkern/tree.h
endif

$(DEPS): $(OSX_HEADERS) $(SRCS)
	$(CC) -MM $(CFLAGS) $(SRCS) 2>/dev/null >$(DEPS) || \
	( \
		for I in $(wildcard *.h); do \
			export $${I//[-.]/_}_DEPS="`sed '/^\#[ \t]*include \?"\(.*\)".*/!d;s//\1/' $$I`"; \
		done; \
		echo -n >$(DEPS); \
		for SRC in $(SRCS); do \
			echo -n "$${SRC%.c}.o: " >>$(DEPS); \
			export SRC_DEPS="`sed '/\#[ \t]*include \?"\(.*\)".*/!d;s//\1/' $$SRC | sort`"; \
			while true; do \
				export SRC_DEPS_OLD="$$SRC_DEPS"; \
				export SRC_DEEP_DEPS=""; \
				for HDR in $$SRC_DEPS; do \
					eval export SRC_DEEP_DEPS="\"$$SRC_DEEP_DEPS \$$$${HDR//[-.]/_}_DEPS\""; \
				done; \
				export SRC_DEPS="`echo $$SRC_DEPS $$SRC_DEEP_DEPS | sed 's/  */\n/g' | sort -u`"; \
				test "$$SRC_DEPS" = "$$SRC_DEPS_OLD" && break; \
			done; \
			echo $$SRC $$SRC_DEPS >>$(DEPS); \
		done; \
	)

-include $(DEPS)

$(OUT): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS) $(LIBS)

clean:
	$(RM) $(OUT) $(CONF) $(OBJS)

distclean: clean
	$(RM) tags $(DEPS)
	$(RM) -r gen

tests/__build-tstamp__: $(OUT) tests/[a-z]* tests/[a-z]*/*
	cd tests && ./build
	touch $@

tests/prlimit-nofile: tests/prlimit-nofile.c
	$(CC) $(CFLAGS) -o $@ $^

test: tests/__build-tstamp__ tests/prlimit-nofile
	cd tests && env $(TEST_ENV) ./run
