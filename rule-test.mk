# rule-test.mk : Test rule caching & execution

thisFile := $(lastword $(MAKEFILE_LIST))

# Invoke this makefile directly to test ./minion.mk
MINION ?= minion.mk

# Don't interfere with other make invocations
OUTDIR = .out/cachetest/

Alias(default).in = Alias(cache-test)

# `cached-rules` is invoked in a sub-make.  Some instances are cached
# and some are not, and an environment variable can modiy their behavior.
Alias(cached-rules).in = $(minion_cache)
minion_cache = Echo(xxx)
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
  TEXT=a $(MKC)
  @grep -q a $(call get,out,Echo(x))
  @grep -q a $(call get,out,Echo(xx))
  @grep -q a $(call get,out,Echo(xxx))
  TEXT=B $(MKC)
  @grep -q a $(call get,out,Echo(x))   # cached
  @grep -q B $(call get,out,Echo(xx))  # not cached
  @grep -q a $(call get,out,Echo(xxx)) # cached
endef

include $(MINION)

