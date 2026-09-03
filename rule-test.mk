# rule-test.mk : Test rule caching & execution

thisFile := $(lastword $(MAKEFILE_LIST))

# Invoke this makefile directly to test ./minion.mk
MINION ?= minion.mk

# Don't interfere with other tests running in parallel
OUTDIR ?= .out/rule-test/

makeSelf = make -f $(thisFile)

default = Alias(cache-test) Alias(graph-test) Alias(clean-test)

#----------------------------------------------------------------
# cache-test
#----------------------------------------------------------------
#
# We will be invoking the makefile recursively, but with a different OUTDIR.

echoxxx = Echo(xxx)

caOUTDIR = .out/cache-test/
caCACHE = $(caOUTDIR)cache.mk
caMAKE = minionCache=echoxxx minionNoCache='Echo(xx)' OUTDIR=$(caOUTDIR) $(makeSelf)


Echo.inherit = Builder
Echo.rule = .PHONY: {@}$(\n){inherit}
Echo.in = $(patsubst %,Echo(%),$(patsubst x%,%,$(filter x%,$(_arg1))))
# TEXT is an un-tracked external variable that influences the rule
Echo.command = @echo echo=$(or $(TEXT),$(_argText))= > {@} {track}
# Reference tracked external dependencies...
Echo.track = $(and $(call _var,Echo.inherit)$(call _shell,echo foo)$(call _wildcard,$(_arg1)*),)


# ASSERT: minionCache accepts *goals*
# ASSERT: indirect dependencies of $(minionCache) are cached
# ASSERT: individual instance is excluded via $(minionNoCache)
# ASSERT: command-line override is detected, bypassing cache
# ASSERT: validity checks for _wildcard, _shell, _var are written
define Alias(cache-test).command
  @echo '#*> cache-test'
  @rm -rf $(caOUTDIR)
  $(caMAKE) 'Print(Echo(xx))' | grep -q echo=xx=
  [ -f $(caCACHE) ]
  TEXT=Z $(caMAKE) 'Print(Echo(xx))' | grep -q echo=Z=  # rule not cached
  TEXT=Z $(caMAKE) 'Print(Echo(x))'  | grep -q echo=x=  # rule cached
  $(caMAKE) TEXT=Z 'Print(Echo(x))'  | grep -q echo=Z=  # cached, but bypassed
  TEXT=Z $(caMAKE) 'Print(Echo(x))'  | grep -q echo=x=  # back to cached version
  grep -q '_cachedIDs = Alias(echoxxx) Echo(x) Echo(xxx)' $(caCACHE)
  grep -q 'ifneq "foo" "$$(shell echo foo)"' $(caCACHE)
  grep -q 'ifneq "Builder" "$$(Echo.inherit)"' $(caCACHE)
endef

#----------------------------------------------------------------
# graph-test
#----------------------------------------------------------------

Alias(graph-test).in = Write(expected-graph)
define Alias(graph-test).command
  @echo '#*> graph-test'
  $(makeSelf) 'Graph(Echo(xxx))' > {@}.out
  diff -u $(call get,out,Write(expected-graph)) {@}.out
endef

define expected-graph

Echo(xxx)
|  
+-> Echo(xx)
    |  
    +-> Echo(x)


endef

#----------------------------------------------------------------
# clean-test: Clean(TARGET) && `make clean [TARGETS...]`
#----------------------------------------------------------------

define Alias(clean-test).command
  @echo '#*> clean-test'

  @# ASSERT: `Clean(TARGET)` cleans target and its descendants (not VOUTDIR)
  @# ASSERT: `Clean(TARGET)` cleans {vvFile} along with {out}  (via cleanCommand)
  @mkdir -p .out
  $(makeSelf) 'Echo(xxx)' > .out/log
  @( cd $(OUTDIR)Echo/ && echo *) | grep 'x x.vv xx xx.vv xxx xxx.vv'
  @$(makeSelf) 'Clean(Echo(xx))' >> .out/log
  @( cd $(OUTDIR)Echo/ && echo *) | grep 'xxx xxx.v'

  @# ASSERT: `make clean TARGET` == Clean(TARGET) and not `make clean`
  @$(makeSelf) 'Echo(xxx)' > .out/log
  @$(makeSelf) clean 'Echo(xx)' >> .out/log
  @( cd $(OUTDIR)Echo/ && echo *x) | grep 'xxx'

  @# ASSERT: `make clean` removes VOUTDIR
  @# ASSERT: `make clean` builds Alias(clean).in targets
  @rm -f .out/write
  @$(makeSelf) clean > .out/log
  @! [[ -d $(VOUTDIR) ]] || (echo '**** VOUTDIR still exists!'; false)
  @grep -q blah .out/write

  @# ASSERT: Clean(TARGET) does not remove "phony" outputs
  touch .out/phony
  @$(makeSelf) 'Clean(Alias(.out/phony))'
  @[[ -f .out/phony ]] || (echo '**** Clean deleted phony target'; false)
endef

Alias(clean).in = Write(data:blah,out:.out/write)

Alias(foo).test = $(foreach _error,,$(call get,undefed,Echo(x)))

#----------------------------------------------------------------
# time-rollup, time-eval, time-cache
#----------------------------------------------------------------

Alias(time).in = Alias(time-rollup) Alias(time-eval) Alias(time-cache)
Alias(time-rollup).in = Time(Call(_rollup,Alias(mongo)))
Alias(time-eval).in = Time(Call(_evalRules,Alias(mongo)))
Alias(time-cache).in = TimeCache(1) TimeCache(100)

Call.inherit = Phony
Call.expr = $$(call $(_argText))
Call.command = @echo '{expr}' $(if $(call or,{expr}),)

Time.inherit = Phony
Time.command = /bin/sh -c "time $(makeSelf) $(foreach a,$(_args),$(call _shellQuote,$a))"

TimeCache.inherit = Phony
define TimeCache.command
  @rm -rf $(OUTDIR)cache.mk
  /bin/sh -c "time $(makeSelf) nada 'minionCache=Alias(mongo)' '_cacheGroupSize=$(_arg1)'"
endef

# mongo (2000 imaginary targets) just a pawn in game of life
Alias(mongo).in = CExe@mongo
mongo = $(strip \
  $(foreach a,0 1 2 3 4 5 6 7 8 9,\
    $(foreach b,0 1 2 3 4 5 6 7 8 9,\
      $(foreach c,0 1 2 3 4 5 6 7 8 9,\
         source$a$b$c.c))))

# Do nothing, but don't look "trivial" or else minion.mk will bypass
# cache file generation.
Alias(nada).in = Phony(nothing)

#----------------------------------------------------------------
# Demo reporting of references to automatic variables
#----------------------------------------------------------------

# during per-instance property
Alias(warn1-demo).command = echo $@
# during class property
Alias(warn2-demo).command = echo {badAt}
Alias.badAt = $@
# during other function
Alias(warn3-demo).command = echo $(call badAt)
badAt = $@

include $(MINION)
