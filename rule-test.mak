#------------------------------------------------------------------------
# Test Minion rule caching & execution
# Set NOISY=1 to see all commands issued.
#------------------------------------------------------------------------

thisFile := $(lastword $(MAKEFILE_LIST))
include $(dir $(thisFile))test-utils.mk

default = Test(cache) Test(graph) Test(clean) Test(collide)

# Invoke this makefile directly to test ./minion.mk
MINION ?= minion.mk

# Don't interfere with other tests running in parallel
OUTDIR ?= .out/rule-test/

Builder.make = NOISY=$(NOISY) MAKEOVERRIDES= MAKEFLAGS= $(MAKE) -f $(thisFile)
Builder.recipe = $(if {noisy},$(subst $(\n)@,$(\n),$(subst $(\n) ,$(\n),$(subst $(\n)  ,$(\n),{inherit}))),{inherit})
Builder.noisy = $(NOISY)

Test.in =
Test.log = $(OUTDIR)$(_arg1).log

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
Echo.out = $(VOUTDIR)/Echo/$(_arg1)
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
  @minionTrace= {make} 'Graph(Echo(xxx))' > {@}.out $(call _!!, graph failed)
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
  @{make} 'Echo(xxx)' > {log}
  @[[ -f {subOUTDIR}Echo/xx ]] $(call _!!,Did not build .out)
  @[[ -f {subOUTDIR}Echo/xx.vv ]] $(call _!!,Did not build .vvFile)
  @[[ -f {subOUTDIR}Echo/x ]] $(call _!!,Did not build dependency)
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
# Test(collide): Test collision detection
#----------------------------------------------------------------

Simple.inherit = Builder
Simple.out = $(_arg1)

colliding = Simple(A) Simple(./A)

define Test(collide).exec
  @# ASSERT: Collisions detected
  ( ! {make} colliding >{log} 2>&1 ) $(call _!!, Did not detect collision)
  grep -q 'Target collision' {log} $(call _!!, No collision error)
  grep -q 'Simple(A).out = A' {log} $(call _!!, No collision description)
endef


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
