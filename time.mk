# time.mk: Some benchmarking targets
include test-utils.mk


default =
all = xi xi2


#----------------------------------------------------------------
# Evaluate as a Make expression the contents of a variable.
#
#   $ export F1='$(words $(call _rollup,Project(100)))'
#   $ time make -f time.mk 'Eval(F1)' 
#   $ time make -f time.mk 'Eval(F1)' slowdownX100=_rollup
#

Eval.inherit = Phony
Eval.var = $(_arg1)
Eval.command = @echo '$(_self) -> "$(call or,$({var}))"'


#----------------------------------------------------------------
# Project(N) : a fictional project with N sources, exes, and tests.
#   This cannot be built, but it can be used as for timing:
#
#   $ time make -f time.mk '$(words $(call _rollup,Project(100)))' slowdownX1001=_rollup
#
Project.inherit = Phony
Project.reps = $(or $(_arg1),1)
Project.rootPatterns = WorkTest(WorkExe(CC(foo<N>.c)))
Project.in = $(foreach n,$(call _range,1,{reps}),$(subst <N>,$n,{rootPatterns}))

WorkTest.inherit = Exec

# Make this non-trivial (each .c file involves inference of CC(...))
WorkExe.inherit = CExe
WorkExe.in = {inherit} @workLibSrcs # exercise indirections
WorkExe.libFlags = -lboost
workLibSrcs = a.c b.c c.c d.c e.c f.c g.c h.c i.c j.c

CC++.optFlags = -Os
CC++.warnFlags = -W -Wall


#----------------------------------------------------------------
# inspect: Detect command-line vars.
#
# Usage:
#   slowdownX1001=inspectVars time make -f time.mk xi
#   slowdownX1001=inspectVars2 time make -f time.mk xi2

# ~80us per rep
xi: ; @echo 'command-line vars: $(if $(call inspectVars),yes,no)'

# ~28us per rep
xi2: ; @echo 'command-line vars: $(if $(call inspectVars2),yes,no)'

inspectVars = $(filter c%,$(foreach v,$(.VARIABLES),$(origin $v)))

startVars := $(.VARIABLES)
inspectVars2 = $(filter c%,$(foreach v,$(startVars),$(origin $v)))

#----------------------------------------------------------------
minionStart=1
include $(or $(MINION),.out/minion.mk)
$(_autoSlowdown)
$(minionEnd)
