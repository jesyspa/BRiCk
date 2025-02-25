#
# Copyright (c) 2019-2020 BedRock Systems, Inc.
#
# This software is distributed under the terms of the BedRock Open-Source License.
# See the LICENSE-BedRock file in the repository root for details.
#

default_target: coq cpp2v
.PHONY: default_target

CMAKE=cmake
COQMAKEFILE=$(COQBIN)coq_makefile

# To avoid "jobserver unavailable" warnings, prepend + to recursive make
# invocations using these variables; + is inferred when $(MAKE) appears
# literally in the invocation, not when $(MAKE) appears indirectly.
# https://stackoverflow.com/a/60706372/53974
CPPMK := $(MAKE) -C build
COQMK := $(MAKE) -f Makefile.coq
DOCMK := $(MAKE) -C doc

# You can override this with a different program which you can use to preview html files within your filesystem.
DOCOPEN ?= xdg-open

ROOT := $(shell pwd)
include Makefile.doc

OPAM_PREFIX := $(shell opam var prefix)
BINDIR = $(OPAM_PREFIX)/bin



all: coq cpp2v test
.PHONY: all





# Build the `cpp2v` tool


# On Darwin, customize the cmake build system to use homebrew's llvm.
SYS := $(shell uname)

BUILDARG=
BUILD_TYPE ?= Release

CPP2V_LOGS := cpp2v-cmake.log cpp2v-make.log

SHELL := /bin/bash

build/Makefile: Makefile CMakeLists.txt
	$(CMAKE) -B build $(BUILDARG) -DCMAKE_BUILD_TYPE=$(BUILD_TYPE) &> cpp2v-cmake.log || { cat cpp2v-cmake.log; exit 1; }

cpp2v: build/Makefile
	+$(CPPMK) cpp2v &> build/cpp2v-make.log || { cat build/cpp2v-make.log; exit 1; }
.PHONY: cpp2v



# Build Coq theories

Makefile.coq Makefile.coq.conf: _CoqProject Makefile
	+$(COQMAKEFILE) -f _CoqProject -o Makefile.coq

# We must extract `coq-minimal` as a task, and share it between
# `build-minimal` and `coq`, because `test` depends on both:
# `test -> test-cpp2v -> build-minimal -> coq-minimal`
# `test -> test-coq -> coq -> coq-minimal`
coq-minimal: theories/lang/cpp/parser.vo
.PHONY: coq-minimal

coq: coq-minimal
	+$(COQMK)
.PHONY: coq

# Pass a few useful targets on to the Coq makefile
%.vo %.vos %.required_vo: Makefile.coq
	+@$(COQMK) $@




# Tests for `cpp2v`

test: test-cpp2v test-coq
.PHONY: test

minimal-install:
	mkdir -p build
	rm -rf build/bedrock
	ln -s $(ROOT)/theories build/bedrock

build-minimal: coq-minimal
	$(MAKE) minimal-install
.PHONY: build-minimal

build-minimal-vos: theories/lang/cpp/parser.vos
	$(MAKE) minimal-install
.PHONY: build-minimal

test-cpp2v: build-minimal cpp2v
	$(MAKE) -C cpp2v-tests CPP2V=$(ROOT)/build/cpp2v
test-cpp2v-vos: build-minimal-vos cpp2v
	$(MAKE) -C cpp2v-tests CPP2V=$(ROOT)/build/cpp2v vos
.PHONY: test-cpp2v

test-coq: cpp2v coq
	$(MAKE) -C tests CPP2V=$(ROOT)/build/cpp2v
.PHONY: test-coq


# Build Coq docs

.PHONY: html coqdocjs doc public redoc

redoc:
	$(MAKE) doc-clean
	$(MAKE) doc

# This target does a quick build of the sphinx output for local testing.
sphinx:
#	Generate html files in `doc/sphinx/_build/html` using coqdoc outputs and
#	other sources in `doc/`
	+$(DOCMK) html

coqdoc: coq coqdocjs
#	Cleanup existing artifacts (if there are any)
	rm -rf html

#	Invoke `coqdoc` using the existing `_CoqProject` file, and move the artifacts
#	out of `html` and into `doc/sphinx/_static/coqdoc`
	+$(COQMK) html
	mkdir -p doc/sphinx/_static/coqdoc
	mv html/* doc/sphinx/_static/coqdoc && rmdir html

html doc: coqdoc
#	Generate html files in `doc/sphinx/_build/html` using coqdoc outputs and
#	other sources in `doc/`
	$(MAKE) sphinx

coqdocjs:
#	Copy (custom) `coqdocjs` resources into `doc/sphinx/_static`, removing all
#	coqdoc artifacts in the process.
	rm -rf doc/sphinx/_static/coqdoc
	mkdir -p doc/sphinx/_static/css/coqdocjs doc/sphinx/_static/js/coqdocjs
	cp -r coqdocjs/extra/resources/*.css doc/sphinx/_static/css/coqdocjs
	cp -r coqdocjs/extra/resources/*.js doc/sphinx/_static/js/coqdocjs

public: html
	rm -rf public
	cp -R doc/sphinx/_build/html public

doc-open: doc
	$(DOCOPEN) doc/sphinx/_build/html/index.html
.PHONY: doc-open



# Install targets (coq, cpp2v, or both)

install-coq: coq
	+$(COQMK) install
.PHONY: install-coq

install-cpp2v: cpp2v
	install -m 0755 build/cpp2v "$(BINDIR)"
.PHONY: install-cpp2v

install: install-coq install-cpp2v
.PHONY: install




# Clean

doc-clean:
	+@$(MAKE) -C doc clean
clean: doc-clean
	rm -rf build
	rm -rf public
	+@$(MAKE) -C cpp2v-tests clean
	+@if test -f Makefile.coq; then $(COQMK) cleanall; fi
	rm -f Makefile.coq Makefile.coq.conf
	find . ! -path '*/.git/*' -name '.lia.cache' -type f -print0 | xargs -0 rm -f
	rm -f $(CPP2V_LOGS)
.PHONY: clean doc-clean






# Packaging

link: coq
	mkdir -p build
	rm -f build/bedrock
	ln -s $(ROOT)/theories build/bedrock
.PHONY: link



release: coq cpp2v
	rm -rf cpp2v
	mkdir cpp2v
	cp -p build/cpp2v cpp2v
	cp -pr theories cpp2v/bedrock
.PHONY: release




touch_deps:
	touch `find . -iname '*.vo'`  || true
	touch `find . -iname '*.vok'` || true
	touch `find . -iname '*.vos'` || true
	touch `find . -iname '*.glob'` || true
	touch `find . -iname '.*.aux'` || true
# Unneeded and fails in CI
#	touch `find cpp2v-tests -iname '*.v'` || true
	touch `find build` || true
.PHONY: touch_deps




deps.pdf: _CoqProject
	coqdep -f _CoqProject -dumpgraphbox deps.dot > /dev/null
	dot -Tpdf -o deps.pdf deps.dot
