# Slow down functions 11x or 101x for more accurate timings.
#
# Usage: Set `minionX11` to a list of function names, and include x11.mk after
# including minion.mk but before minionEnd:
#
#    minionStart=1
#    include minion.mk
#    include x11.mk
#    $(minionEnd)
#
X11 = $(if $(foreach x,1 2 3 4 5 6 7 8 9 0,$(if $($0_),)),)$($0_)
X101 = $(if $(foreach x,1 2 3 4 5 6 7 8 9 0,\
           $(foreach y,1 2 3 4 5 6 7 8 9 0,\
              $(if $($0_),))),)$($0_)

$(foreach x,X11 X101,\
  $(foreach f,$(minion$x),\
    $(eval $f_ = $(value $f))\
    $(eval $f = $$($x))\
    $(info $f_ = $(value $f_))))


