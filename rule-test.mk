# rule-test.mk : Test rule caching & execution

thisFile := $(lastword $(MAKEFILE_LIST))

# Invoke this makefile directly to test ./minion.mk
MINION ?= minion.mk

# Don't interfere with other make invocations
OUTDIR = .out/cachetest/

Alias(default).in = Alias(cache-test)

#----------------------------------------------------------------
# cache-test
#----------------------------------------------------------------

# `cached-rules` is invoked in a sub-make.  Some instances are cached
# and some are not, and an environment variable can modiy their behavior.
Alias(cached-rules).in = $(minion_cache)
minion_cache_exclude = Echo(xx)

Echo.inherit = Builder
Echo.rule = .PHONY: {@}$(\n){inherit}
Echo.in = $(patsubst %,Echo(%),$(patsubst x%,%,$(_arg1)))
Echo.command = @echo $(TEXT) > {@}

MKC = make -f $(thisFile) cached-rules

# ASSERT: indirect dependencies of $(minion_cache) are cached
# ASSERT: individual instance is excluded via $(minion_cache_exclude)
define Alias(cache-test).command
  @rm -rf $(OUTDIR)
  @mkdir -p $(OUTDIR)
  TEXT=a $(MKC) 'minion_cache=Echo(xxx)'
  grep -q a $(call get,out,Echo(x))
  grep -q a $(call get,out,Echo(xx))
  grep -q a $(call get,out,Echo(xxx))
  TEXT=B $(MKC) 'minion_cache=Echo(xxx)'
  grep -q a $(call get,out,Echo(x))   # cached
  grep -q B $(call get,out,Echo(xx))  # not cached
  grep -q a $(call get,out,Echo(xxx)) # cached
endef

#----------------------------------------------------------------
# speed-test
#----------------------------------------------------------------

# Create 2000 targets just as a burden for cache file generation
Alias(mongo).in = CExe@mongo
mongo = $(strip \
  $(foreach a,0 1 2 3 4 5 6 7 8 9,\
    $(foreach b,0 1 2 3 4 5 6 7 8 9,\
      $(foreach c,0 1 2 3 4 5 6 7 8 9,\
         source$a$b$c.c))))

# Do nothing, but don't look "trivial" or else minion.mk will bypass
# cache file generation.
Alias(nada).in = Phony(nothing)
Phony(nothing).in =

define Alias(speed-test).command
  @mkdir -p $(OUTDIR)
  @rm -rf $(OUTDIR)cache.mk
  time make -f $(thisFile) nada 'minion_cache=Alias(mongo)' '_cache-N=1'
  @rm -rf $(OUTDIR)cache.mk
  time make -f $(thisFile) nada 'minion_cache=Alias(mongo)' '_cache-N=10'
endef


include $(MINION)

# 3200 create cache (N=1)
#  950 create cache (N=12)
#  800 create cache (N=50)
#  600 $(call _evalRules,Alias(mongo))
#  340 $(call _rollup,Alias(mongo))
#   57 make nada (built cache)
