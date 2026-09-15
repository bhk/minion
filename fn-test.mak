#------------------------------------------------------------------------
# Test make functions implemented in minion.mk
#------------------------------------------------------------------------

default = #nothing
MINION ?= minion.mk
include $(MINION)


# Validate _eq? (used by _expectEQ)

$(if $(call _eq?,1,),$(error eq))
$(if $(call _eq?,,1),$(error eq))
$(if $(call _eq?,1,2),$(error eq))
$(if $(call _eq?,1,11),$(error eq))
$(if $(call _eq?,1,1),,$(error eq))

# $(call _expectEQ,A,B): error (with diagnostics) if A is not the same as B
#
_expectEQ = $(if $(call _eq?,$1,$2),,$(error Values differ:$(\n)A: $(_qv)$(\n)B: $(call _qv,$2)$(\n)))
true = $(if $1,1)
not = $(if $1,,1)


# constants

$(call _expectEQ,$(\s)$(\t)$(\H)$[$;$], 	#(,))


# Built-in classes

WVAR = test

define WWrule
.out/Write/WVAR :   | 
	@echo '#-> Write(WVAR)'
	@mkdir -p .out/Write/
	@echo '_vv=.@printf !`%b!` `test` > !@.' > .out/Write/WVAR.vv
	@printf "%b" 'test' > .out/Write/WVAR

_vv =
-include .out/Write/WVAR.vv
ifneq "$(_vv)" ".@printf !`%b!` `test` > !@."
  .out/Write/WVAR: .out/FORCE
endif

endef

$(call _expectEQ,\
  $(call get,rule,Write(WVAR)),\
  $(value WWrule))


#------------------------------------------------------------------------
# Check presence of SCAM exports not otherwise used by minion
#------------------------------------------------------------------------

# get

TA.p  = <A.p>
TA.r  = <A.r:$(_argText);{s}>
TB.inherit = TA
TB(a).s := <B(a).s:$$(_argText);{}>
TB(a).r  = <B(a).r:$(_class);{inherit};{p}>

# file ID
$(call _expectEQ,\
  $(call get,out,filename),\
  filename)

# instance-defined, simple variable
$(call _expectEQ,\
  $(call get,s,TB(a)),\
  <B(a).s:$$(_argText);{}>)

# cached access
$(call _expectEQ,\
  $(call get,s,TB(a)),\
  <B(a).s:$$(_argText);{}>)


# instance-defined, recursive variable
# + {inherit}, {prop}
# + class-defined simple & recursive variables
$(call _expectEQ,\
  $(call get,r,TB(a)),\
  <B(a).r:TB;<A.r:a;<B(a).s:$$(_argText);{}>>;<A.p>>)
