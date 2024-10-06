# minion.mk

# User Classes
#
# The following classes may be overridden by user makefiles.  Minion
# attaches no property definitions to them; it just provides a default
# inheritance.  User makefiles may not override other make variables defined
# in this file, except for a few cases where "?=" is used (see below).

Builder.inherit ?= _Builder
CC++.inherit ?= _CC++
CC.inherit ?= _CC
CExe++.inherit ?= _CExe++
CExe.inherit ?= _CExe
CCBase.inherit ?= _CCBase
Copy.inherit ?= _Copy
Exec.inherit ?= _Exec
GZip.inherit ?= _GZip
Link.inherit ?= _Link
Phony.inherit ?= _Phony
Print.inherit ?= _Print
Run.inherit ?= _Run
Test.inherit ?= _Test
Write.inherit ?= _Write


#--------------------------------
# Built-in Classes
#--------------------------------

# Alias(TARGETNAME) : Generate a phony rule whose {out} matches TARGETNAME.
#     {command} and/or {in} are supplied by the user makefile.
#
Alias.inherit = Phony
Alias.out = $(subst :,\:,$(_argText))
Alias.in =


# Variants(TARGETNAME) : Build {all} variants of TARGETNAME.  Each variant
#    is defined in a separate rule so they can all proceed concurrently.
#
Variants.inherit = Phony
Variants.in = $(foreach v,{all},_Variant($(_argText),V:$v))


# Variant(TARGETNAME,V:VARIANT) : Build VARIANT of TARGETNAME.
#
_Variant.inherit = Phony
_Variant.in =
_Variant.command = @$(MAKE) -f $(word 1,$(MAKEFILE_LIST)) --no-print-directory $(call _shellQuote,$(subst =,:,$(_arg1))) V=$(call _shellQuote,$(call _namedArg1,V))


# Phony(INPUTS) : Generate a phony rule.
#
#   A phony rule does not generate an output file.  Therefore, Make cannot
#   determine whether its result is "new" or "old", so it is always
#   considered "old", and its recipe will be executed whenever it is listed
#   as a target.
#
_Phony.inherit = _IsPhony Builder
_Phony.command = @true
_Phony.message =


# _IsPhony : Mixin that defines properties as appropriate for all phony
#    targets; can be used to make any class phony.
#
_IsPhony.rule = .PHONY: {@}$(\n){inherit}
_IsPhony.mkdirs = # not a real file => no need to create directory
_IsPhony.vvFile = # always runs => no point in validating


# CCBase(SOURCE) : Base class for invoking a compiler.  This is expected to
#    serve as a template or example for actual projects, which will
#    typically override properties at the CCBase or CC/CC++ level.
#
#    "-MF" is used to generate a make include file that lists all implied
#    depenencies (those that do not appear on the command line -- included
#    headers).
#
_CCBase.inherit = Builder
_CCBase.outExt = .o
_CCBase.command = {compiler} -c -o {@} {<} {options} -MMD -MP -MF {@}.d
_CCBase.rule = {inherit}-include {@}.d$(\n)
_CCBase.options = {srcFlags} {objFlags} {libFlags} $(addprefix -I,{includes})
_CCBase.srcFlags = -std=c99 -Wall -Werror
_CCBase.objFlags = -O2
_CCBase.libFlags =
_CCBase.includes =


# CC(SOURCE) : Compile a C file to an object file.
#
_CC.inherit = CCBase
_CC.compiler = gcc


# CC++(SOURCE) : Compile a C++ file to an object file.
#
_CC++.inherit = CCBase
_CC++.compiler = g++


# Link(INPUTS) : Link an executable.
#
_Link.inherit = Builder
_Link.outExt =
_Link.command = {compiler} -o {@} {^} {flags} 
_Link.flags = {libFlags}
_Link.libFlags =


# CExe(INPUTS) : Link a command-line C program.
#
_CExe.inherit = _Link
_CExe.compiler = gcc
_CExe.inferClasses = CC.c


# CExe++(INPUTS) : Link a command-line C++ program.
#
_CExe++.inherit = _Link
_CExe++.compiler = g++
_CExe++.inferClasses = CC.c CC++.cpp CC++.cc


# Exec(COMMAND) : Run a command, capturing what it writes to stdout.
#
#    By default, the first ingredient is an executable or shell command, and
#    it is passed as arguments the {execArgs} property and all other
#    ingredients.  Override {exec} to change what is to be executed while
#    retaining other behavior.
#
#    Note: If you override {exec} such that {<} is not the executable, then
#    you should also probably override {inferClasses}.
#
_Exec.inherit = Builder
_Exec.command = ( {exportPrefix} {exec} ) > {@} || ( rm -f {@}; false )
_Exec.exec = {<} {execArgs} $(wordlist 2,9999,{^})
_Exec.execArgs =
_Exec.outExt = .out
_Exec.inferClasses = CExe.c CExe++.cpp CExe++.cc


# Test(COMMAND) : Run a command (as per Exec) updating an OK file on success.
#
_Test.inherit = Exec
_Test.command = {exportPrefix} {exec}$(\n)touch {@}
_Test.outExt = .ok


# Run(COMMAND) : run command (as per Exec).
#
_Run.inherit = _IsPhony Exec
_Run.command = {exportPrefix} {exec}


# Copy(INPUT)
# Copy(INPUT,out:OUT)
# Copy(INPUT,dir:DIR)
#
#   Copy a single artifact.
#   OUT, when provided, specifies the destination file.
#   DIR, when provided, gives the destination directory.
#   Otherwise, $(VOUTDIR)$(_class) is the destination directory.
#
_Copy.inherit = Builder
_Copy.out = $(or $(call _namedArg1,out),{inherit})
_Copy.outDir = $(or $(call _namedArg1,dir),$(VOUTDIR)$(_class)/)
_Copy.command = cp {<} {@}


# Print(INPUT) : Write artifact to stdout.
#
_Print.inherit = Phony
_Print.command = @cat {<}


# GZip(INPUT) :  Compress an artifact.
#
_GZip.inherit = Exec
_GZip.exec = gzip -c {^}
_GZip.outExt = %.gz


# Write(VAR)
# Write(VAR,out:OUT)
#
#   Write the value of a variable to a file.
#
_Write.inherit = Builder
_Write.out = $(or $(call _namedArg1,out),{inherit})
_Write.command = @$(call _printf,{data}) > {@}
_Write.data = $($(_arg1))
_Write.in =


# Builder(ARGS):  Base class for builders.  See minion.md for details.

# Core builder properties
_Builder.needs = {inIDs} {upIDs} {depsIDs} {ooIDs}
_Builder.out = {outDir}{outName}

define _Builder.rule
{@} : {^} $(call get,out,{upIDs} {depsIDs}) | $(call get,out,{ooIDs})
$(call _recipe,{recipe})
$(foreach F,{vvFile},_vv =
-include $F
ifneq "$$(_vv)" "{vvValue}"
  {@}: $(_forceTarget)
endif
)
endef

define _Builder.recipe
$(if {message},@echo $(call _shellQuote,{message}))
$(if {mkdirs},@mkdir -p {mkdirs})
$(foreach F,{vvFile},@echo '_vv={vvValue}' > $F)
{command}
endef

# Shorthands
_Builder.@ = {out}
_Builder.< = $(firstword {^})
_Builder.^ = {inFiles}

_Builder.in = $(_args)
# list of ([ID,]FILE) pairs for inputs
_Builder.inPairs = $(call _inferPairs,$(foreach i,$(call _expand,{in},in),$i$(if $(filter %$],$i),$$$(call get,out,$i))),{inferClasses})
_Builder.inIDs = $(call _pairIDs,{inPairs})
_Builder.inFiles = $(call _pairFiles,{inPairs})

# up: dependencies specified by the class
_Builder.up =
_Builder.upIDs = $(call _expand,{up},up)
_Builder.up^ = $(call get,out,{upIDs})

# oo: order-only dependencies.
_Builder.oo =
_Builder.ooIDs = $(call _expand,{oo},oo)

# deps: direct dependencies not covered by {in} or {up}
_Builder.deps =
_Builder.depsIDs = $(call _expand,{deps})
_Builder.deps^ = $(call get,out,{depsIDs})

# inferClasses: a list of CLASS.EXT patterns
_Builder.inferClasses =

_Builder.outExt = %
_Builder.outDir = $(dir {outBasis})
_Builder.outName = $(foreach e,$(notdir {outBasis}),$(basename $e)$(subst %,$(suffix $e),{outExt}))
_Builder.outBasis = $(VOUTDIR)$(call _outBasis,$(_class),$(_argText),{outExt},$(call get,out,$(filter $(_arg1),$(word 1,$(call _expand,{in},in)))),$(_arg1))

# message to be displayed when the command executes (if non-empty)
_Builder.message ?= \#-> $(_self)

# directories to be created prior to commands in recipe
_Builder.mkdirs = $(sort $(dir {@} {vvFile}))

# This may be prepended to individual command lines to export environment variables
# listed in {exports}
_Builder.exportPrefix = $(foreach v,{exports},$v=$(call _shellQuote,{$v}) )
_Builder.exports =

# Validity values
_Builder.vvFile ?= {outBasis}.vv
_Builder.vvValue = $(call _vvEnc,{command},{@})


# $(call _vvEnc,DATA,OUTFILE) : Encode DATA to be shell-safe (within single
#   quotes) and Make-safe (within double-quotes or RHS of assignment) and
#   echo-safe (across /bin/echo and various shell builtins)
_vvEnc = .$(subst ',`,$(subst ",!`,$(subst `,!b,$(subst $$,!S,$(subst $(\n),!n,$(subst $(\t),!+,$(subst \#,!H,$(subst $2,!@,$(subst \,!B,$(subst !,!1,$1)))))))))).#'

# $(call _lazy,MAKESRC) : Encode MAKESRC for inclusion in a recipe so that
# it will be expanded when and if the recipe is executed.  Otherwise, all
# "$" characters will be escaped to avoid expansion by Make. For example:
# $(call _lazy,$$(info X=$$X))
_lazy = $(subst $$,$(\e),$1)

# Indent recipe lines and escape them for rule-phase expansion.  Un-escape
# _lazy encoding to enable on-demand execution of functions.
_recipe = $(subst $(\e),$$,$(subst $$,$$$$,$(subst $(\t)$(\n),,$(subst $(\n),$(\n)$(\t),$(\t)$1)$(\n))))


#--------------------------------
# Minion internal classes
#--------------------------------


# _File(FILENAME) : Do nothing, and treat FILENAME as the output.  This class
#    is used by `get` so that plain file names can be supplied instead of
#    instance names.  Property evaluation logic short-cuts the handling of
#    File instances, so inheritance is not available.
#
_File.out = $(_self)
_File.rule =
_File.needs =


# _Goal(TARGETNAME) : Generate a phony rule for an instance or indirection
#    goal.  Its {out} should match the name provided on the command line,
#    and its {in} is the named instance or indirection.
#
_Goal.inherit = Alias
_Goal.in = $(_argText)


# _HelpGoal(TARGETNAME) : Generate a rule that invokes `_help!`
#
_HelpGoal.inherit = Alias
_HelpGoal.command = @true$(call _lazy,$$(call _help!,$(call _escArg,$(_argText))))


#--------------------------------
# Variable & Function Definitions
#--------------------------------

# V defaults to the first word of Variants.all
V ?= $(word 1,$(Variants.all))

# All Minion build products are placed under this directory
OUTDIR ?= .out/

# Build products for the current V are placed here
VOUTDIR ?= $(OUTDIR)$(if $V,$V/)

# Is $1 a "safe" arg to "rm -rf"?  (Catch accidental ".", "..", "/" etc.)
_safeToClean = $(filter-out . ..,$(subst /, ,$1))

# $(call minion_alias,GOAL) returns an instance if GOAL is an alias,
#   or an empty value otherwise.  User makefiles can override this to
#   support other types of aliases.
minion_alias ?= $(_aliasID)

# Character constants

\s := $(if ,, )
\t := $(if ,,	)
\H := \#
[[ := {
]] := }
[ := (
] := )
; := ,
define \n


endef
# This character may not appear in `command` values, except via _lazy.
\e = 

_eq? = $(findstring $(subst x$1,1,x$2),1)
_shellQuote = '$(subst ','\'',$1)'#'  (comment to fix font coloring)
_printfEsc = $(subst $(\n),\n,$(subst $(\t),\t,$(subst \,\\,$1)))
_printf = printf "%b" $(call _shellQuote,$(_printfEsc))

# Quote a (possibly multi-line) $1
_qvn = $(if $(findstring $(\n),$1),$(subst $(\n),$(\n)  | ,$(\n)$1),$2$1$2)
_qv = $(call _qvn,$1,')#'

# $(call _?,FN,ARGS..): same as $(call FN,ARGS..), but logs args & result.
_? = $(call __?,$$(call $1,$2,$3,$4,$5),$(call $1,$2,$3,$4,$5))
__? = $(info $1 -> $2)$2

# $(call _log,NAME,VALUE): Output "NAME: VALUE" when NAME matches the
#   pattern in `$(minion_debug)`.
_log = $(if $(filter $(minion_debug),$1),$(info $1: $(call _qvn,$2)))

# $(call _eval,NAME,VALUE): Log + eval VALUE
_eval = $(_log)$(eval $2)

# $(call _evalRules,IDs,EXCLUDES) : Evaluate rules of IDs and their transitive dependencies
_evalRules = $(foreach i,$(call _rollupEx,$(sort $(_isInstance)),$2),$(call _eval,eval-$i,$(call get,rule,$i)))

# Escape an instance argument as a Make function argument
_escArg = $(subst $[,$$[,$(subst $],$$],$(subst $;,$$;,$(subst $$,$$$$,$1))))

# _cache_rule : Include a generated makefile that defines rules for IDs in
#    $(minion_cache) and their transitive dependencies, excluding IDs in
#    $(minion_cache_exclude).  Defer recipe expansion to the rule processing
#    phase, because the recipe involves computing every rule.
#
define _cache-rule
$(VOUTDIR)cache.mk : $(MAKEFILE_LIST) ; $(call _cache-recipe,$(_cache-ids),$(_cache-excludes))
-include $(VOUTDIR)cache.mk
endef

_cache-excludes = $(filter %$],$(call _expand,$(minion_cache_exclude)))
_cache-ids = $(filter-out $(_cache-excludes),$(call _rollup,$(call _expand,@minion_cache)))

# write out this many rules per printf command line
_cache-N = 12

# $1=CACHED-IDS  $2=EXCLUDED-IDS
define _cache-recipe
@echo 'Updating Minion cache...'
@mkdir -p $(@D)
@echo '_cachedIDs = $1' > $@_tmp_
$(foreach g,$(call _group,$1,$(_cache-N)),
@$(call _printf,$(foreach i,$(call _ungroup,$g),
$(call get,rule,$i)
$(if $2,_$i_needs = $(filter $2,$(call _depsOf,$i))
))) >> $@_tmp_)
@mv $@_tmp_ $@
endef


#--------------------------------
# Help system
#--------------------------------

define _helpMessage
$(word 1,$(MAKEFILE_LIST)) usage:

   make                     Build the target named "default"
   make GOALS...            Build the named goals
   make help                Show this message
   make help GOALS...       Describe the named goals
   make help 'C(A).P'       Compute value of property P for C(A)
   make clean               `$(call get,command,Alias(clean))`

Goals can be ordinary Make targets, Minion instances (`Class(Arg)`),
variable indirections (`@var`), or aliases. Note that instances must
be quoted for the shell.

endef

_fmtList = $(if $(word 1,$1),$(subst $(\s),$(\n)   , $(strip $1)),(none))

_isProp = $(filter $].%,$(lastword $(subst $], $],$1)))

# instance, indirection, alias, other
_goalType = $(if $(_isProp),Property,$(if $(_isInstance),$(if $(_isClassInvalid),InvalidClass,Instance),$(if $(_isIndirect),Indirect,$(if $(_aliasID),Alias,Other))))

_helpDeps = Direct dependencies: $(call _fmtList,$(call get,needs,$1))$(\n)$(\n)Indirect dependencies: $(call _fmtList,$(call filter-out,$(call get,needs,$1),$(call _rollup,$(call get,needs,$1))))


define _helpInvalidClass
"$1" looks like an instance with an invalid class name;
`$(_idC).inherit` is not defined.  Perhaps a typo?

endef


define _helpInstance
$1 is an instance.

{out} = $(call get,out,$1)

$(foreach p,$(if $(call _describeProp,$1,command),command,rule),{$p} = $(call _qvn,$(call get,$p,$1)))

$(_helpDeps)
endef


define _helpIndirect
$1 is an indirection on the following variable:

$(call _describeVar,$(_ivar),   )

It expands to the following targets: $(call _fmtList,$(call _expand,$1))
endef


define _helpAlias
$1 is an alias for $(minion_alias).
$(if $(filter Alias$[%,$(minion_alias)),
It is defined by:$(foreach v,$(filter Alias($1).%,$(.VARIABLES)),
$(call _describeVar,$v,   )
))
$(call _helpDeps,$(minion_alias))

It generates the following rule: $(call _qvn,$(call get,rule,$(minion_alias)))
endef


# $1 = C(A).P; $2 = description;  $(id) = C(A); $p = P
define _helpPropertyInfo
$(id) inherits from: $(call _chain,$(call _idC,$(id)))

{$p} $(if $(if $2,,1),is not defined!,is defined by:

$2

Its value is: $(call _qv,$(call get,$p,$(id))))

endef

_helpProperty = $(foreach p,$(or $(lastword $(subst $].,$] ,$1)),$(error Empty property name in $1)),$(foreach id,$(patsubst %$].$p,%$],$1),$(call _helpPropertyInfo,$1,$(call _describeProp,$(id),$p))))


define _helpOther
Target "$1" is not generated by Minion.  It may be a source
file or a target defined by a rule in the Makefile.
endef


_help! = \
  $(if $(filter help,$1),\
    $(if $(filter-out help,$(MAKECMDGOALS)),,$(info $(_helpMessage))),\
    $(info $(call _help$(call _goalType,$1),$1)))


#--------------------------------
# Rules
#--------------------------------

_forceTarget = $(OUTDIR)FORCE

Alias(clean).command ?= $(if $(call _safeToClean,$(VOUTDIR)),rm -rf $(VOUTDIR),@echo '** make clean is disabled; VOUTDIR is unsafe: "$(VOUTDIR)"' ; false)

# This will be the default target when `$(minion_end)` is omitted (and
# no goal is named on the command line)
_error_default: ; $(error Makefile used minion_start but did not call `$$(minion_end)`)

.SUFFIXES:
$(_forceTarget):

define _epilogue
  # Check OUTDIR
  ifneq "/" "$(patsubst %/,/,$(OUTDIR))"
    $(error OUTDIR must end in "/")
  endif

  ifndef MAKECMDGOALS
    # .DEFAULT_GOAL only matters when there are no command line goals
    .DEFAULT_GOAL = default
    _goalIDs := $(call _goalID,default)
  else ifneq "" "$(filter $$%,$(MAKECMDGOALS))"
    # "$*" captures the entirety of the goal, including embedded spaces.
    $$%: ; @#$(info $$$* = $(call _qv,$(call or,$$$*)))
    %: ; @echo 'Cannot build "$*" alongside $$(...)' && false
  else ifneq "" "$(filter help,$(MAKECMDGOALS))"
    _goalIDs := $(MAKECMDGOALS:%=_HelpGoal$[%$])
    _error = $(info $(subst $(\n),$(\n)   ,ERROR: $1)$(\n))
  else
    _goalIDs := $(foreach g,$(MAKECMDGOALS),$(call _goalID,$g))
  endif

  ifeq "" "$(strip $(call get,needs,$(_goalIDs)))"
    # Trivial goals do not benefit from a cache.  Importantly, avoid the
    # cache when handling `help` (targets may conflict with cache file) or
    # `clean` (so we can recover from a corrupted cache file).
  else ifdef minion_cache
    $(call _eval,eval-cache,$(value _cache-rule))
    # If the cache makefile does NOT exist yet then _cachedIDs is unset and
    # will be set to "%" here to disable _evalRules, because Make will
    # immediately restart and rule computation would be a waste of time.
    _cachedIDs ?= %
  endif

  $(call _evalRules,$(_goalIDs),$(_cachedIDs))
endef


# SCAM source exports:

# base.scm

_error = $(error $1)
_isInstance = $(filter %$],$1)
_isIndirect = $(findstring @,$(filter-out %$],$1))
_aliasID = $(if $(filter s% r%,$(flavor Alias($1).in) $(flavor Alias($1).command)),Alias($1))
_goalID = $(or $(call minion_alias,$1),$(if $(or $(_isInstance),$(_isIndirect)),_Goal($1)))
_ivar = $(filter-out %@,$(subst @,@ ,$1))
_ipat = $(if $(filter @%,$1),%,$(subst $(\s),,$(filter %( %% ),$(subst @,$[ ,$1) % $(subst @, $] ,$1))))
_EI = $(call _error,$(if $(filter %@,$1),Invalid target (ends in '@'): $1,Indirection '$1' references undefined variable '$(_ivar)')$(if $(and $(_self),$2),$(\n)Found while expanding $(if $(filter _Goal$[%,$(_self)),command line goal $(patsubst _Goal(%),%,$(_self)),$(_self).$2)))
_expandX = $(foreach w,$1,$(if $(findstring @,$w),$(if $(findstring $[,$w)$(findstring $],$w),$w,$(if $(filter u%,$(flavor $(call _ivar,$w))),$(call _EI,$w,$2),$(patsubst %,$(call _ipat,$w),$(call _expandX,$($(call _ivar,$w)),$2)))),$w))
_expand = $(if $(findstring @,$1),$(call _expandX,$1,$2),$1)
_set = $(eval $$1 := $$2)$2
_fset = $(eval $$1 = $(if $(filter 1,$(word 1,1$20)),$$(or ))$(subst \#,$$(\H),$(subst $(\n),$$(\n),$2)))$1
_once = $(if $(filter u%,$(flavor _o~$1)),$(call _set,_o~$1,$($1)),$(value _o~$1))
_argError = $(call _error,Argument '$(subst `,,$1)' is mal-formed:$(\n)   $(subst `,,$(subst `$], *$]* ,$(subst `$[, *$[*,$1)))$(\n)$(if $(C),during evaluation of $(C)($(A))))
_argGroup = $(if $(findstring `$[,$(subst $],$[,$1)),$(if $(findstring $1,$2),$(_argError),$(call _argGroup,$(subst $(\s),,$(foreach w,$(subst $(\s) `$],$]` ,$(patsubst `$[%,`$[% ,$(subst `$], `$],$(subst `$[, `$[,$1)))),$(if $(filter %`,$w),$(subst `,,$w),$w))),$1)),$1)
_argHash2 = $(subst `,,$(foreach w,$(subst $(if ,,`,), ,$(call _argGroup,$(subst :,`:,$(subst $;,$(if ,,`,),$(subst $],`$],$(subst $[,`$[,$1)))))),$(if $(findstring `:,$w),,:)$w))
_argHash = $(if $(or $(findstring $[,$1),$(findstring $],$1),$(findstring :,$1)),$(or $(value _h~$1),$(call _set,_h~$1,$(_argHash2))),:$(subst $;, :,$1))
_hashGet = $(patsubst $2:%,%,$(filter $2:%,$1))
_describeVar = $2$(if $(filter r%,$(flavor $1)),$(if $(findstring $(\n),$(value $1)),$(subst $(\n),$(\n)$2,define $1$(\n)$(value $1)$(\n)endef),$1 = $(value $1)),$1 := $(subst $(\n),$$(\n),$(subst $$,$$$$,$(value $1))))

# objects.scm

_idC = $(if $(findstring $[,$1),$(word 1,$(subst $[, ,$1)))
_isClassInvalid = $(filter u%,$(flavor $(_idC).inherit))
_pup = $(filter-out &%,$($(word 1,$1).inherit) &$1)
_walk = $(if $1,$(if $(findstring s,$(flavor $(word 1,$1).$2)),$1,$(call _walk,$(_pup),$2)))
_E1 = $(call _error,Undefined property '$2' for $(_self) was referenced$(if $(filter u%,$(flavor $(_class).inherit)),;$(\n)$(_class) is not a valid class name ($(_class).inherit is not defined),$(if $3,$(if $(filter ^%,$3), from {inherit} in,$(if $(filter &&%,$3), from {$2} in, during evaluation of)):$(\n)$(call _describeVar,$(if $(filter &%,$3),$(foreach w,$(lastword $(subst ., ,$3)),$(word 1,$(call _walk,$(word 1,$(subst &, ,$(subst ., ,$3))),$w)).$w),$(if $(filter ^%,$3),$(subst ^,,$(word 1,$3)).$2,$3)))))$(\n))
_cx = $(if $1,$(if $(value &$1.$2),&$1.$2,$(call _fset,$(if $4,$(subst $],],~$(_self).$2),&$1.$2),$(foreach w,$(word 1,$1).$2,$(if $(filter s%,$(flavor $w)),$(subst $$,$$$$,$(value $w)),$(subst },$(if ,,,&$$0$]),$(subst {,$(if ,,$$$[call .,),$(subst {inherit},$(if $(findstring {inherit},$(value $w)),$$(call $(call _cx,$(call _walk,$(if $4,$(_class),$(_pup)),$2),$2,^$1))),$(value $w)))))))),$(_E1))
.& = $(if $(findstring s,$(flavor $(_self).$1)),$(call _cx,$(_self),$1,$2,1),$(if $(findstring s,$(flavor &$(_class).$1)),&$(_class).$1,$(call _fset,&$(_class).$1,$(value $(call _cx,$(call _walk,$(_class),$1),$1,$2)))))
. = $(if $(filter s%,$(flavor ~$(_self).$1)),$(value ~$(_self).$1),$(call _set,~$(_self).$1,$(call $(.&))))
_E0 = $(call _error,Mal-formed target '$(_self)'; $(if $(filter $[%,$(_self)),no CLASS before '$[',$(if $(findstring $[,$(_self)),no '$]' at end,unbalanced '$]')))
get = $(foreach _self,$2,$(foreach _class,$(if $(findstring $[,$(_self)),$(or $(filter-out |%,$(subst $[, |,$(filter %$],$(_self)))),$(_E0)),$(if $(findstring $],$(_self)),$(_E0),_File)),$(call .,$1)))
_argText = $(patsubst $(_class)(%),%,$(_self))
_args = $(call _hashGet,$(call _argHash,$(patsubst $(_class)(%),%,$(_self))))
_arg1 = $(word 1,$(_args))
_namedArgs = $(call _hashGet,$(call _argHash,$(patsubst $(_class)(%),%,$(_self))),$1)
_namedArg1 = $(word 1,$(_namedArgs))
_describeProp = $(if $1,$(if $(filter u%,$(flavor $(word 1,$1).$2)),$(call _describeProp,$(or $(_idC),$(_pup)),$2),$(call _describeVar,$(word 1,$1).$2,   )$(if $(and $(filter r%,$(flavor $(word 1,$1).$2)),$(findstring {inherit},$(value $(word 1,$1).$2))),$(\n)$(\n)...wherein {inherit} references:$(\n)$(\n)$(call _describeProp,$(or $(_idC),$(_pup)),$2))))
_chain = $(if $1,$(call _chain,$(_pup),$2 $(word 1,$1)),$(filter %,$2))

# tools.scm

_pairIDs = $(filter-out $$%,$(subst $$, $$,$1))
_pairFiles = $(filter-out %$$,$(subst $$,$$ ,$1))
_inferPairs = $(if $2,$(foreach w,$1,$(or $(foreach x,$(word 1,$(filter %$],$(patsubst %$(or $(suffix $(call _pairFiles,$w)),.),%($(call _pairIDs,$w)),$2))),$x$$$(call get,out,$x)),$w)),$1)
_depsOf = $(or $(value _&deps-$1),$(call _set,_&deps-$1,$(or $(sort $(foreach w,$(filter %$],$(call get,needs,$1)),$w $(call _depsOf,$w))),$(if ,, ))))
_rollup = $(sort $(foreach w,$(filter %$],$1),$w $(call _depsOf,$w)))
_rollupEx = $(if $1,$(call _rollupEx,$(filter-out $3 $1,$(sort $(filter %$],$(call get,needs,$(filter-out $2,$1))) $(foreach w,$(filter $2,$1),$(value _$w_needs)))),$2,$3 $1),$(filter-out $2,$3))
_relpath = $(if $(filter /%,$2),$2,$(if $(filter ..,$(subst /, ,$1)),$(error _relpath: '..' in $1),$(or $(foreach w,$(filter %/%,$(word 1,$(subst /,/% ,$1))),$(call _relpath,$(patsubst $w,%,$1),$(if $(filter $w,$2),$(patsubst $w,%,$2),../$2))),$2)))
_group = $(if $1,$(subst | ,|0,$(subst ||,,$(join $(subst |,|1,$1),$(subst $(patsubst %,|,$(wordlist 1,$2,$1)),$(patsubst %,|,$(wordlist 1,$2,$1))|,$(patsubst %,|,$1))) )))
_ungroup = $(subst |1,|,$(subst |0, ,$1))

# outputs.scm

_fsenc = $(subst >,@r,$(subst <,@l,$(subst /,@D,$(subst ~,@T,$(subst !,@B,$(subst :,@C,$(subst $],@-,$(subst $[,@+,$(subst |,@1,$(subst @,@_,$1))))))))))
_outBX = $(subst @D,/,$(subst $(\s),,$(patsubst /%@_,_%@,$(addprefix /,$(subst @_,@_ ,$(_fsenc))))))
_outBS = $(_fsenc)$(if $(findstring %,$3),,$(suffix $4))$(if $4,$(patsubst _/$(OUTDIR)%,_%,$(if $(filter %$],$2),_)$(subst //,/_root_/,$(subst //,/,$(subst /../,/_../,$(subst /./,/_./,$(subst /_,/__,$(subst /,//,/$4))))))),$(call _outBX,$2))
_outBasis = $(if $(filter $5,$2),$(_outBS),$(call _outBS,$1$(subst _$(or $5,|),_|,_$2),$(or $5,out),$3,$4))

ifndef minion_start
  $(eval $(value _epilogue))
else
  minion_end = $(eval $(value _epilogue))
endif
