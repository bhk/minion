# time.mk: Some benchmarking targets
include test-utils.mk


default = Work(10) xi xi2

#----------------------------------------------------------------
# work:  A large fictional project for timing rule generation.
#
# Usage:
#
#   make -f time.mk 'Work(1)'
#   make -f time.mk 'Work(10000)'
#
# Rule generation example timing (2023 MacBook Pro):
#    30010 rules / 12 seconds = 2500 rules/sec

getRules = $(foreach i,$1,$(call get,rule,$i))

#----------------------------------------------------------------
# Work(N,FN) : Compute rules for N fictional C files, and pass
#   them to FN (default = 'eval').
#
Work.inherit = Builder
Work.in =
Work.reps = $(or $(_arg1),1)
Work.evalFn = $(or $(word 2,$(_args)),eval)
Work.rootPatterns = WorkTest(WorkExe(CC(foo<N>.c)))
Work.roots = $(foreach n,$(call _range,1,{reps}),$(subst <N>,$n,{rootPatterns}))
Work.rollups = $(call _rollup,$(call _expand,{roots}))
Work.rules = $(call getRules,{rollups})
Work.doWork = $(call {evalFn},{rules})
Work.command = @echo '$(words {rollups}) rules computed [{doWork}]'

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
include $(or $(MINION),minion.mk)
$(_autoSlowdown)
$(minionEnd)
