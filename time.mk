# time.mk: Some benchmarking targets

#----------------------------------------------------------------
# default:  A large fictional project for timing rule generation.
default = Work(Alias(all))


all = Alias(tests) Alias(progs)
tests = ExecTest@LinkTest@CC@files
progs = LinkC@files

# Work[IN] : Compute rules for rollups, but do not evaluate them.
#
Work.inherit = Builder
Work.in =
Work.rollups = $(call _rollup,$(_args))
Work.rules = $(foreach i,{rollups},$(words $(call get,rule,$i)))
Work.command = @echo '$(words {rules}) rules computed'

x10 = $(foreach x,$1,$x0 $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9)
files = $(addsuffix .c,$(call x10,$(call x10,foo bar baz)))

LinkTest.inherit = LinkC
LinkTest.in = {inherit} {libSrcs}
LinkTest.libFlags = -lboost
LinkTest.libSrcs = a.c b.c c.c d.c e.c f.c g.c h.c i.c j.c

ExecTest.inherit = Exec

CC++.optFlags = -Os
CC++.warnFlags = -W -Wall


#----------------------------------------------------------------
# inspect: Detect command-line vars.

# ~100us per rep
xi: ; @echo 'command-line vars: $(if $(call inspectVars),yes,no)'

# ~28us per rep
xi2: ; @echo 'command-line vars: $(if $(call inspectVars2),yes,no)'

inspectVars = $(filter c%,$(foreach v,$(.VARIABLES),$(origin $v)))

startVars := $(.VARIABLES)
inspectVars2 = $(filter c%,$(foreach v,$(startVars),$(origin $v)))


#----------------------------------------------------------------
minionStart=1
include $(or $(MINION),minion.mk)
include slowdown.mk
$(minionEnd)
