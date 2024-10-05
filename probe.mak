# Testbed for examining Make's behavior

#
# var: Show value of $(var) in a this instance and an empty makefile.
#
#  * `make var var=MAKEFLAGS -j2`:  MAKEFLAGS differs between
#    reading and rule processing phases.
#
#  * MAKEFLAGS & MFLAGS: Parsing MAKEFLAGS to detect `-r`, etc, is
#    non-trivial, whereas $(findstring r,$(word 1,MFLAGS)) appears to work.
#
var ?= .VARIABLES
subflags = -R
emptyget = $(shell make $1 -f - <<<'$$(info $$($(var)))_x:;@true')

var1 := $($(var))

var: ; @true\
  $(info phase1  : $(var) = $(var1))\
  $(info phase2  : $(var) = $($(var)))\
  $(info empty   : $(var) = $(call emptyget,$(subflags)))


#
# subdiff: Diff $(var) between this instance and `make $(subflags)`
#
diff = $(info -: $(sort $(filter-out $2,$1)))\
       $(info +: $(sort $(filter-out $1,$2)))

subdiff: ; @true\
  $(info This instance --> `make $(subflags)`:)\
  $(info $(call diff,$($(var)),$(call emptyget,$(subflags))))


#
# Diff $(var) between two submakes, one with $(subflags).
#
flagdiff: ; @true\
  $(info `make` --> `make $(subflags)`)\
  $(info $(call diff,$(emptyget),$(call emptyget,$(subflags))))


#
# Demonstrate parallelization
#
#   * `make par` takes 5 seconds
#   * `make par -j5` takes 1 second.
#   * `make par setflags=-j5` takes 1 second => setting MAKEFLAGS=-jN
#     affects the current Make instance.
#

ifdef setflags
  MAKEFLAGS := $(setflags)
endif

par: 1.sleep 2.sleep 3.sleep 4.sleep 5.sleep

%.sleep: ; @echo $* start && sleep 1 && echo $* end


#
# Invoke self as sub-make
#
#  * `make submake setflags=-j5` warns "disabling jobserver".
#    Setting MAKEFLAGS=-jN creates this problem with submakes.
#

submake ?= par

submake: ; @$(MAKE) -f $(word 1,$(MAKEFILE_LIST)) $(submake)


#
# Expansion of recipes
#
#  * When recipes are expanded at build time, they can contain
#    newlines without tabs, even when in a one-line rule context.
#

define lazyRecipe
# comment
echo foo
@echo bar
echo baz
endef

test-lazy:
	$(lazyRecipe)

test-lazy2: ; $(lazyRecipe)
