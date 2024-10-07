# minion.mk and demo.md are version-controlled snapshots of build
# products.  `make all` will build them and warn if they differ from the
# corresponding files in this directory.  `make promote` will copy them from
# ./.out to this directory.

MO = .out/minion.mk
TO = .out/minion.mk.ok
DO = .out/demo.md

.PHONY: default minion demo clean test time scam promote

use-color = $(filter-out dumb,$(TERM))
diff-cmd = @diff -q $1 || (diff -u $(if $(use-color),--color=always) $1 ; false)

default: minion demo
minion: $(MO) $(TO) ; $(call diff-cmd,minion.mk $(MO))
demo: minion $(DO) ; $(call diff-cmd,demo.md $(DO))
clean: ; rm -rf .out
test: $(TO)
time: ; time make -R -f time.mk
scam: ; scam minion.scm

promote:
	@$(call promote-cmd,minion.mk)
	@$(call promote-cmd,demo.md)

promote-cmd = @\
   if ( diff -q $1 .out/$1 ) ; then \
     true ; \
   else \
      echo "updating $1..." && cp .out/$1 $1 ; \
   fi


$(MO): *.scm minion.mk Makefile
	@echo '#*> MO: Minion output'
	@mkdir -p $(@D)
	sed '1,/SCAM/!d' minion.mk > $@.1
	scam minion.scm $@.2
	cat $@.1 $@.2 > $@

$(TO): $(MO) fn-test.mk rule-test.mk
	@echo '#*> TO: Test Output'
	@mkdir -p $(@D)
	make -f fn-test.mk MINION=$<
	( make -f rule-test.mk MINION=$< ) > $@.log || ( cat $@.log ; false )
	touch $@

$(DO): minion.mk demo/*
	@echo '#*> DO: Demo Output'
	@mkdir -p $(@D)
	@rm -rf demo/.out
	cd demo && MAKEFLAGS= scam run-session.scm demo-session.md -- -o ../$@
	rm demo/Makefile
