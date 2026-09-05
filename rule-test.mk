# rule-test.mk : Test rule caching & execution
thisFile := $(lastword $(MAKEFILE_LIST))
include $(dir $(thisFile))test-utils.mk

default = Test(cache) Test(graph) Test(clean)

# Invoke this makefile directly to test ./minion.mk
MINION ?= minion.mk

# Don't interfere with other tests running in parallel
OUTDIR ?= .out/rule-test/

Builder.make = NOISY=$(NOISY) MAKEOVERRIDES= MAKEFLAGS= $(MAKE) -f $(thisFile)
Builder.recipe = $(if {noisy},$(subst $(\n)@,$(\n),$(subst $(\n) ,$(\n),$(subst $(\n)  ,$(\n),{inherit}))),{inherit})
Builder.noisy = $(NOISY)

Test.in =
Test.log = {outDir}rtlog

#----------------------------------------------------------------
# Test(cache)
#----------------------------------------------------------------
#
# We will be invoking the makefile recursively, but with a different OUTDIR.

echoxxx = Echo(xxx)

Test(cache).subOUTDIR = .out/cache-test/
Test(cache).cache = {subOUTDIR}cache.mk
Test(cache).make = minionCache=echoxxx minionNoCache='Echo(xx)' OUTDIR={subOUTDIR} {inherit}

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
define Test(cache).exec
  @rm -rf {subOUTDIR}
  @{make} 'Echo(xx)' > {log}  $(call _!!,cache submake failed)
  @[[ -f {cache} ]] $(call _!!, Cache not generated)
  @TEXT=Z {make} 'Print(Echo(xx))' | grep -q echo=Z=  $(call _!!,should not be cached)
  @TEXT=Z {make} 'Print(Echo(x))'  | grep -q echo=x=  $(call _!!,should be cached)
  @{make} TEXT=Z 'Print(Echo(x))'  | grep -q echo=Z=  $(call _!!,should be bypassed)
  @TEXT=Z {make} 'Print(Echo(x))'  | grep -q echo=x=  $(call _!!,should be cached)
  @grep -q '_cachedIDs = Alias(echoxxx) Echo(x) Echo(xxx)' {cache}
  @grep -q 'ifneq "foo" "$$(shell echo foo)"' {cache}
  @grep -q 'ifneq "Builder" "$$(Echo.inherit)"' {cache}
endef

#----------------------------------------------------------------
# Test(graph)
#----------------------------------------------------------------

Test(graph).in = Write(expected-graph)
define Test(graph).exec
  @{make} 'Graph(Echo(xxx))' > {@}.out $(call _!!, graph failed)
  @diff -u $(call get,out,Write(expected-graph)) {@}.out $(call _!!, does not match)
endef

define expected-graph

Echo(xxx)
|  
+-> Echo(xx)
    |  
    +-> Echo(x)


endef

#----------------------------------------------------------------
# Test(clean): Clean(TARGET) && `make clean [TARGETS...]`
#----------------------------------------------------------------

Test(clean).subOUTDIR = $(OUTDIR)clean-test/
Test(clean).make = OUTDIR={subOUTDIR} {inherit} IN_CLEAN_TEST=1

define Test(clean).exec
  @# ASSERT: `Clean(TARGET)` cleans target and its descendants (not VOUTDIR)
  @# ASSERT: `Clean(TARGET)` cleans {vvFile} along with {out} (via .cleanCommand)
  @mkdir -p {subOUTDIR}
  @{make} 'Echo(xxx)' > {log}
  @( cd {subOUTDIR}Echo/ && echo *) | grep -q 'x x.vv xx xx.vv xxx xxx.vv'
  @{make} 'Clean(Echo(xx))' >> {log}
  @! [[ -f {subOUTDIR}Echo/xx ]] $(call _!!, Did not clean .out)
  @! [[ -f {subOUTDIR}Echo/xx.vv ]] $(call _!!, Did not clean .vvFile)
  @! [[ -f {subOUTDIR}Echo/x ]] $(call _!!, Did not clean dependency)
  @# ASSERT: Clean(TARGET) does not remove {out} for phony rules
  @touch .out/phony
  @{make} 'Clean(Alias(.out/phony))' >> {log}
  @[[ -f .out/phony ]] $(call _!!, Clean deleted phony target)

  @# ASSERT: `make clean TARGET` == Clean(TARGET) and not `make clean`
  @{make} 'Echo(xxx)' > {log}
  @{make} clean 'Echo(xx)' >> {log}
  @( echo {subOUTDIR}Echo/*x ) | grep -q 'Echo/xxx'

  @# ASSERT: `make clean` removes VOUTDIR
  @# ASSERT: `make clean` builds `clean` prereqs
  @rm -f .out/ctClean
  @{make} clean > {log}
  @! [[ -d {subOUTDIR} ]] $(call _!!, VOUTDIR still exists)
  @[[ -f .out/ctClean ]] $(call _!!, prereq Write(...) did not run)
endef

ifdef IN_CLEAN_TEST
  clean = Write(data:blah,out:.out/ctClean)
endif


#----------------------------------------------------------------
# time-rollup, time-eval, time-cache
#----------------------------------------------------------------

time = time-rollup time-eval time-cache
time-rollup = Time(Call(_rollup,Alias(mongo)))
time-eval = Time(Call(_evalRules,Alias(mongo)))
time-cache = TimeCache(1) TimeCache(100)

Call.inherit = Phony
Call.expr = $$(call $(_argText))
Call.command = @echo '{expr}' $(if $(call or,{expr}),)

Time.inherit = Phony
Time.command = /bin/sh -c "time {make} $(foreach a,$(_args),$(call _shellQuote,$a))"

TimeCache.inherit = Phony
define TimeCache.command
  @rm -rf $(OUTDIR)cache.mk
  /bin/sh -c "time {make} nada 'minionCache=Alias(mongo)' '_cacheGroupSize=$(_arg1)'"
endef

# mongo (2000 imaginary targets) just a pawn in game of life
mongo = CExe@mongoFiles
mongoFiles = $(strip \
  $(foreach a,0 1 2 3 4 5 6 7 8 9,\
    $(foreach b,0 1 2 3 4 5 6 7 8 9,\
      $(foreach c,0 1 2 3 4 5 6 7 8 9,\
         source$a$b$c.c))))

# Do nothing, but don't look "trivial" or else minion.mk will bypass
# cache file generation.
nada = Phony(nothing)

#----------------------------------------------------------------
# Demo reporting of references to automatic variables
#----------------------------------------------------------------

# during per-instance property
warn1-demo =
Alias(warn1-demo).command = echo $@
# during class property
warn2-demo =
Alias(warn2-demo).command = echo {badAt}
Alias.badAt = $@
# during other function
warn3-demo =
Alias(warn3-demo).command = echo $(call badAt)
badAt = $@

include $(MINION)
