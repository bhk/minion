# rule-test.mk : Test rule caching & execution

thisFile := $(lastword $(MAKEFILE_LIST))

# Invoke this makefile directly to test ./minion.mk
MINION ?= minion.mk

# Don't interfere with other make invocations
OUTDIR = .out/cachetest/

makeSelf = $(MAKE) -f $(thisFile)

Alias(default).in = Alias(cache-test) Alias(graph-test)

#----------------------------------------------------------------
# cache-test
#----------------------------------------------------------------

# `cached-rules` is invoked in a sub-make.  Some instances are cached
# and some are not, and an environment variable can modiy their behavior.
Alias(cached-rules).in = $(minionCache)
minionNoCache = Echo(xx)

Echo.inherit = Builder
Echo.rule = .PHONY: {@}$(\n){inherit}
Echo.in = $(patsubst %,Echo(%),$(patsubst x%,%,$(_arg1)))
Echo.command = @echo $(TEXT) > {@}

# ASSERT: indirect dependencies of $(minionCache) are cached
# ASSERT: individual instance is excluded via $(minionNoCache)
define Alias(cache-test).command
  @echo '#*> cache-test'
  @rm -rf $(OUTDIR)
  @mkdir -p $(OUTDIR)
  TEXT=a $(makeSelf) cached-rules 'minionCache=Echo(xxx)'
  grep -q a $(call get,out,Echo(x))
  grep -q a $(call get,out,Echo(xx))
  grep -q a $(call get,out,Echo(xxx))
  TEXT=B $(makeSelf) cached-rules 'minionCache=Echo(xxx)'
  grep -q a $(call get,out,Echo(x))   # cached
  grep -q B $(call get,out,Echo(xx))  # not cached
  grep -q a $(call get,out,Echo(xxx)) # cached
endef

#----------------------------------------------------------------
# Graph test
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
  @echo '#*> graph-test'
  @mkdir -p $(OUTDIR)
  @rm -rf $(OUTDIR)cache.mk
  time $(makeSelf) nada 'minionCache=Alias(mongo)' '_cacheGroupSize=1'
  @rm -rf $(OUTDIR)cache.mk
  time $(makeSelf) nada 'minionCache=Alias(mongo)' '_cacheGroupSize=10'
endef


include $(MINION)
