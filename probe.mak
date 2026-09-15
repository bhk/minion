#------------------------------------------------------------------------
# Testbed for testing and examining Make's behavior
#------------------------------------------------------------------------

probeFile := $(lastword $(MAKEFILE_LIST))
makeThis = $(MAKE) -f $(probeFile)

\s := $(if ,, )
\t := $(if ,,	)
\H := \#
\q = "#"
[ := (
] := )
define \n


endef

_eq? = $(findstring $(subst $20,1,$10),1)
_qv = '$1'

# $(call _expectEQ,A,B): error (with diagnostics) if A is not the same as B
#
_expectEQ = #
true = $(if $1,1)
not = $(if $1,,1)

ifneq "" "$(filter default,$(or $(MAKECMDGOALS),default))"
  _expectEQ = $(if $(call _eq?,$1,$2),,$(error Values differ:$(\n)A: $(_qv)$(\n)B: $(call _qv,$2)$(\n)))
  $(info probe.mak: testing...)
else
  SKIPTESTS = 1
endif


default: ;@true


#------------------------------------------------------------------------
# Tests & interactive targets
#------------------------------------------------------------------------

#
# double-expansion of expressions (currently used in `.`)
#

$(call _expectEQ,file,$(call or,$$(origin _qv)))


#
# var: Show value of $(var) in different stages:
#
#    1. Reading phase: makefile parsing & immediate expansion
#    2. Rule processing: recipe expansion/running
#    3. In an empty sub-make's reading phase (inherited variables)
#
#  * `make var var=MAKEFLAGS -j2`: shows that MAKEFLAGS differs between
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
# Demonstrate parallelization & sub-make problems
#
#   * `make par` takes 5 seconds
#   * `make par -j5` takes 1 second.
#   * `make par setflags=-j5` takes 1 second => setting MAKEFLAGS=-jN
#     affects the current Make instance.
#  * `make submake setflags=-j5` warns "disabling jobserver".
#    Setting MAKEFLAGS=-jN creates this problem with submakes.
#
ifdef setflags
  $(info MAKEFLAGS := $(setflags))
  MAKEFLAGS := $(setflags)
endif

par: 1.sleep 2.sleep 3.sleep 4.sleep 5.sleep

%.sleep: ; @echo $* start && sleep 1 && echo $* end

submakeGoal ?= par

submake: ; @$(makeThis) $(submakeGoal)


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

lazy-test:
	$(lazyRecipe)

lazy2-test: ; $(lazyRecipe)


#
# Variable name characters
#
#  * We can define and use '@' prior to rule processing phase, but during
#    rule processing phase it will use Make's automatic definition.
#
#  * $(VAR) is a problem when VAR contains ":" ... even if it is expanded
#    from a var or function call.
#
#  * $(call VAR) is a problem when VAR contains ":" or ")" ... even if those
#    are expanded from vars!
#
#  * Make 3.81
#       a<b = A<B
#       a>b = A<B
#       a$(EQ)n = A=B (if)
#       a$Cn = A:B (if)
#       a$(if ,,:)b = A:B (if)
#       a$Hb = A#B (if)
#       a$(if ,,\#)b =
#       @ = var-test now; but was MYDEF before rule processing.
#
# For Minion, we care only about:
#
#  * Spaces, which might appear in some memoization variables.
#
#  * Parentheses are used in instance names, and in turn instance-specific
#    property definitions.  These characters break $(VAR) and $(call VAR),
#    but fortunately not `$(value VAR)`, which is what we use when reading
#    property definitions.
#
#  * The following are allowed in class argument lists, and in turn instance
#    names, so assigning instance-specific properties woudld require
#    variable names that include them: :, =, *, <, >
#
#    Note that $(var:...=...) conflicts with Make's pattern substitution
#    syntax.
#

a b = A B
a<b = A<B
a>b = A>B
p* = P*
a$(if ,,:)b = A:B
a$(if ,,=)b = A=B
C(a).p = CAP

$(call _expectEQ,A B,$(a b))
$(call _expectEQ,A<B,$(a<b))
$(call _expectEQ,A>B,$(a>b))
$(call _expectEQ,P*,$(p*))
$(call _expectEQ,A:B,$(a:b))
$(call _expectEQ,A=B,$(a=b))
$(call _expectEQ,CAP,$(value C(a).p))

# Supposedly in Make 3.82 "x y=1" does not work whereas "x$(if ,, )y=1" does.
x$(if ,, )y = X Y
$(call _expectEQ,X Y,$(x y))

# other cases...

E = =
C = :
H = \#
L = (
R = )
P = %

# a and b below illustrate how Make interprets expressions
a = !A!
b = !B!
a$(if ,,\#)b = A\#B
a)b = A)B
a(b)c = A(B)C
abcName = a(b)c
a$(if ,,:%=%)b = A:%=%B

@ = MYDEF

PRE@ := $@
ifneq "$@" "MYDEF"
  $(error Cannot override "@" prior in expansion phase)
endif

show-vars:
	@echo '$$(a b)             = $(a b)'
	@echo '$$(a>b)             = $(a>b)'
	@echo '$$(a$$En)            = $(a$Eb)'
	@echo '$$(a#b)             = $(a#b)'
	@echo '$$(a:b)             = $(a:b)'
	@echo '$$(a$$(if ,,:)%=%b)  = $(a$(if ,,:%=)%b)       ***'
	@echo '$$(call a:%=%b)     = $(call a:%=%b)       ***'
	@echo '$$(call a$$C$$P$$E$$Pb) = $(call a$C$P$E$Pb)       ***'
	@echo '$$(value a:%=%b)    = $(value a:%=%b)'
	@echo '$$(a)b)             = $(a$Rb)'
	@echo '$$(call a)b)        = $(call a$Rb)      ***'
	@echo '$$(call a(b)c)      = $(call a(b)c)         ***'
	@echo '$$(call $$(abcName)) = $(call a(b)c)         ***'
	@echo '$$(@) = $@ now; but was $(PRE@) before rule processing.'


#
# Escaping characters in targets
#
# Make 3.81:
#   * `a\ b` escapes "a b", as target or prereq.
#   * `a*b` globs as prereq (and as target!).  "Glob" means if there no file
#      matching the wildcard expression, then the wildcard expression
#      remains unchanges.
#   * `a\*b` does NOT escape the "*" (the "\" remains).
#   * `a\:b` escapes "a:b" in target; NOT in prereq.
#   * `a\=b` escapes "a=b" in prereq; NOT in target.
#

.PHONY: minion.md

m*d: ; @echo 'A: $$@ = "$@"'
a*b: ; @echo 'B: $$@ = "$@"'
m\*d: ; @echo 'C: $$@ = "$@"'
a\ b: ; @echo 'D: $$@ = "$@"'
a\:b: ; @echo 'E: $$@ = "$@"'
a\\\:b: ; @echo 'F: $$@ = "$@"'
a\b: ; @echo 'G: $$@ = "$@"'
a\#b: ; @echo 'H: $$@ = "$@"'
a$Eb: ; @echo 'I: $$@ = "$@"'
a\=b: ; @echo 'J: $$@ = "$@"'

wc1: m*d m\*d a\ b ; @echo '$@="$@";  $$^ = "$^"'
wc2: minion.md ; @echo '$$@ = "$@";  $$^ = "$^"'
wc3: a*b ; @echo '$$@ = "$@";  $$^ = "$^"'
wc\:x: ; @echo 'wcx1: $$@ = "$@";  $$^ = "$^"'     # make wc4:x
wc\\\:x: ; @echo 'wcx2: $$@ = "$@";  $$^ = "$^"'
#wc4: wc:x ; @echo '$$@ = "$@";  $$^ = "$^"' # ERROR: target pattern contains no %
wc5: wc\:x ; @echo '$$@ = "$@";  $$^ = "$^"'
wc7: a\b ; @echo '$$@ = "$@";  $$^ = "$^"'
wc8: a\#b ; @echo '$$@ = "$@";  $$^ = "$^"'
wc9: a\:b ; @echo '$$@ = "$@";  $$^ = "$^"'
wc10: a\=b ; @echo '$$@ = "$@";  $$^ = "$^"'


#
# Examine escaping of characters in `ifeq`, etc.
#

ifndef SKIPTESTS

  enc1 := a\$(\H)\\$(\H)\\\$(\H)

  # test ifeq syntax
  # Funny encoding of backslashes that precede # !
  ifneq ($(enc1),a\\\#\\\\\#\\\\\\\#)
    $(error FAILURE)
  endif

  enc2 := $(\s)$(\t)\a\\b,$(\n)"c))(d\#e"

  # Parenthesis encoding: needs to escape leading spaces, $, parens, #, \n
  #  
  ifneq ($(enc2), $(\s)	\a\\b,$(\n)"c$]$]$[d\#e")
    $(info A = '$(enc2)')
    $(info B = ' $(\s)	\a\\b,$(\n)"c$]$]$[d\#e"')
    $(error FAILURE)
  endif

  # Double-quote encoding: need to escape $, ", #, \n
  #
  ifneq "$(enc2)" " 	\a\\b,$(\n)$(\q)c))(d\#e$(\q)"
    $(error FAIL)
  endif
endif


overrides: ; @echo MAKEOVERRIDES=$(MAKEOVERRIDES)
