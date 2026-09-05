# Usage notes:
#
# ./minion.mk and ./demo.md are version-controlled snapshots of build
# products.  `make` will build new versions of them ($(MO) and $(DO)) and
# then, if they successfully build, compare them to the ./ version.  If they
# differ, `make` will fail.
#
# `make promote` copies the build versions of $(MO) and $(DO) to "./".
#

# Output files
MO = .out/minion.mk
TO = .out/minion.mk.ok
DO = .out/demo.md

.PHONY: default minion demo clean test time scam promote promote-minion promote-demo

use-color = $(filter-out dumb,$(TERM))
diff-cmd = @diff -q $1 || (diff -u $(if $(use-color),--color=always) $1 ; echo '*** $@ promote pending!' ; false)
promote-cmd = @ [[ -f $1 ]] && diff -q $1 .out/$1 || ( echo "updating $1..." && cp .out/$1 $1 )


# Build minion and demo output files, then warn (fail) if they differ.
default: minion demo
minion: $(MO) $(TO) ; $(call diff-cmd,minion.mk $(MO))
demo: minion $(DO) ; $(call diff-cmd,demo.md $(DO))

# Copy updated minion and demo output files to ./
promote: promote-minion promote-demo
promote-minion: ; @$(call promote-cmd,minion.mk)
promote-demo: ;  @$(call promote-cmd,demo.md)

test: $(TO)
time: ; time make -R -f time.mk
clean: ; rm -rf .out

# Generate new minion.mk from ./minion.mk and Scam sources
$(MO): *.scm minion.mk Makefile
	@echo '#*> MO: Minion output'
	@mkdir -p $(@D)
	sed '1,/SCAM/!d' minion.mk > $@.1
	scam minion.scm $@.2
	cat $@.1 $@.2 > $@

# Run tests on minion.mk
$(TO): $(MO) fn-test.mk rule-test.mk
	@echo '#*> TO: Test Output'
	@mkdir -p $(@D)
	make -f fn-test.mk MINION=$<
	( MINION=$< make -f rule-test.mk ) > $@.log || ( cat $@.log ; false )
	touch $@

# Generate new demo.md
$(DO): minion.mk demo/*
	@echo '#*> DO: Demo Output'
	@mkdir -p $(@D)
	@rm -rf demo/.out
	cd demo && MAKEFLAGS= scam run-session.scm demo-session.md -- -o ../$@
	rm demo/Makefile
