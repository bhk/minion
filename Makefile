# Usage notes:
#
# ./minion.mk and ./demo.md are version-controlled snapshots of build
# products.  `make promote` and `make promote-demo` can be used to
# update them (after careful inspection).
#
#   make               : Build minion, test, and fail if promote is needed
#   make minion        : Build and test minion (demo is used as a test)
#   make promote       : Replace ./minion.mk
#   make demo          : Run demo and diff result with ./demo.md
#   make promote-demo  : Replace ./demo.md
#
# Note that the "snapshot" version of minion.mk is also treated as *source*
# for the portion that precedes the Scam-generated functions.  demo.md,
# however, is generated from demo/demo-session.md.

MAKEFLAGS += -rR
.SUFFIXES:

SCAM = scam --build-dir .scam

# Output files
MO = .out/minion.mk
DO = .out/demo.md
MOK = $(MO).ok
DOK = $(DO).ok
TOKs = $(patsubst %,.out/%.ok,$(testMakefiles))
testMakefiles = $(wildcard *.mak)


.PHONY: default minion promote demo promote-demo clean time

default: $(MOK) ; @$(diff) minion.mk $(MO)
minion: $(MOK) ; @diff -q minion.mk $(MO) || true
promote: $(MOK) ; mv $(MO) minion.mk
demo: $(DOK)
promote-demo: $(DO) ; mv $(DO) demo.md

clean: ; rm -rf .out .scam demo/.scam
time: ; time make -f time.mak

$(MOK): $(MO) $(TOKs) $(DOK) ; @touch $@

# Build $(DO) and ensure it matches ./demo.md
$(DOK): $(DO) ; $(diff) demo.md $< && touch $@

# Run demo on $(MO)
$(DO): $(TOKs) demo/*
	@echo '#*> $@ ...'
	@mkdir -p $(@D)
	rm -rf .out/demo/
	mkdir .out/demo
	cp demo/* .out/demo/
	cd .out/demo && MAKEFLAGS= $(SCAM) run-session.scm demo-session.md -- -o ../../$@

# $(TOKs): Run makefile tests
.out/%.mak.ok: %.mak $(MO) test-utils.mk
	@echo '#*> $@ ...'
	@mkdir -p $(@D)
	MINION=$(MO) make -f $<
	touch $@


# Generate new minion.mk from ./minion.mk and Scam sources
$(MO): *.scm minion.mk
	@echo '#*> $@ ...'
	@mkdir -p $(@D)
	sed '1,/SCAM/!d' minion.mk > $@.1
	$(SCAM) minion.scm $@.2
	cat $@.1 $@.2 > $@

use-color = $(filter-out dumb,$(TERM))
diff = diff -u $(if $(use-color),--color=always)
