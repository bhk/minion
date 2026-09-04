# Slow down functions for more accurate timings.
#
# Usage:
# 
# 1)  $(call _slowdown,FACTOR,FUNCNAME)
#
#     This will cause FUNC to be repeated NUM times each time it is called.
#
# 2)  When invoking make, set `slowdownX<NUM>=<FUNC>`.  When this makefile is
#     included, it will slow down the named functions.
#
#     E.g.:   $ time make slowdownX101=evalRules
#

# $(call _words,LENGTH,WORD) : return LENGTH repetitions of WORD
_words = $(if $(word $1,$2),$(wordlist 1,$1,$2),$(call _words,$1,$2 $2))

# $(call _getXFunc,NREPS) -> name of XFunc (a function that evals $0_ NREPS times)
_getXFunc = $(if $(filter u%,$(flavor _X$1)),$(eval _X$1 = $(_xfuncBody)))_X$1
_xfuncBody = $(subst x ,$$(if $$($$0_),),$(wordlist 2,999999,$(call _words,$1,x)) )$$($$0_)

# Example:
#   $(foreach f,$(call _getXFunc,5),$(info $f = $(value $f)))

# $(call _slowdown,FACTOR,FUNCNAME)
_slowdown = \
  $(eval $2_ = $(value $2))\
  $(eval $2 = $$($(_getXFunc)))

# Automatically apply `slowdownX...` variables
$(foreach v,$(filter slowdownX%,$(.VARIABLES)),\
   $(call _slowdown,$(subst slowdownX,,$v),$($v)))
