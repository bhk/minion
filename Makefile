# Usage notes:
#
# ./minion.mk and ./demo.md are version-controlled snapshots of build
# products.  `make` will build new versions of them ($(MO) and $(DO)) and
# then, if they successfully build, compare them to the ./ version.  If they
# differ, `make` will fail.
#
# `make promote` copies the built versions of $(MO) and $(DO) to "./".
#
# Note that the "snapshot" version of minion.mk is also treated as *source*
# for the portion that precedes the Scam-generated functions.  demo.md,
# however, is generated from demo/demo-session.md.
#

SCAM = scam --build-dir .scam

# Output files
MO = .out/minion.mk
TO = .out/minion.mk.ok
DO = .out/demo.md

.PHONY: default minion demo clean test time promote promote-minion promote-demo

use-color = $(filter-out dumb,$(TERM))
diff-cmd = @diff -q $1 || (diff -u $(if $(use-color),--color=always) $1 ; echo '*** $@ promote pending!' ; false)
promote-cmd = @ [[ -f $1 ]] && diff -q $1 .out/$1 || ( echo "updating $1..." && cp .out/$1 $1 )


# Build minion and demo output files, then warn (fail) if they differ.
default: minion demo
minion: $(MO) $(TO) ; $(call diff-cmd,minion.mk $(MO))
demo: $(MO) $(DO) ; $(call diff-cmd,demo.md $(DO))

# Copy updated minion and demo output files to ./
promote: promote-minion promote-demo
promote-minion: ; @$(call promote-cmd,minion.mk)
promote-demo: ;  @$(call promote-cmd,demo.md)

test: $(TO)
time: ; time make -R -f time.mk
clean: ; rm -rf .out .scam demo/.scam

# Generate new minion.mk from ./minion.mk and Scam sources
$(MO): *.scm minion.mk Makefile
	@echo '#*> MO: Minion output'
	@mkdir -p $(@D)
	sed '1,/SCAM/!d' minion.mk > $@.1
	$(SCAM) minion.scm $@.2
	cat $@.1 $@.2 > $@

# Run tests on minion.mk
$(TO): $(MO) fn-test.mk rule-test.mk
	@echo '#*> TO: Test Output'
	@mkdir -p $(@D)
	MINION=$< make -f fn-test.mk
	MINION=$< make -f rule-test.mk
	touch $@

# Run demo on $(MO)
$(DO): $(MO) demo/*
	rm -rf .out/demo
	cp -R demo .out/demo
	rm -rf .out/demo/.out .out/demo/.scam
	cd .out/demo && MAKEFLAGS= $(SCAM) run-session.scm demo-session.md -- -o ../../$@

# Run demo on ./minon.mk
$(DO)-old: minion.mk demo/*
	@echo '#*> DO: Demo Output'
	@mkdir -p $(@D)
	@rm -rf demo/.out demo/.scam
	cd demo && MAKEFLAGS= $(SCAM) run-session.scm demo-session.md -- -o ../$@
	rm demo/Makefile
