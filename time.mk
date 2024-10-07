# time.mk: A large fictional project for timing rule generation.

Alias(default).in = Work(Alias(all))

Alias(all).in = Alias(tests) Alias(progs)
Alias(tests).in = ExecTest@LinkTest@CC@files
Alias(progs).in = LinkC@files

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

minionStart=1
include $(or $(MINION),minion.mk)
include x11.mk
$(minionEnd)
