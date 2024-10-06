# fn_test.mk : Test make functions implemented in minion.mk

Alias(default).in = #nothing
MINION ?= minion.mk
include $(MINION)

true = $(if $1,1)
not = $(if $1,,1)

# $(call _expectEQ,A,B): error (with diagnostics) if A is not the same as B
_expectEQ = $(if $(call _eq?,$1,$2),,$(error Values differ:$(\n)A: $(_qv)$(\n)B: $(call _qv,$2)$(\n)))


# _eq?

$(if $(call _eq?,1,),$(error eq))
$(if $(call _eq?,,1),$(error eq))
$(if $(call _eq?,1,2),$(error eq))
$(if $(call _eq?,1,11),$(error eq))
$(if $(call _eq?,1,1),,$(error eq))


# constants

$(call _expectEQ,$(\s)$(\t)$(\H)$([[)$(]])$[$;$], 	#{}(,))


# _shellQuote

$(call _expectEQ,$(call _shellQuote,a),'a')
$(call _expectEQ,$(call _shellQuote,'a'),''\''a'\''')


# _printfEsc

$(call _expectEQ,$(call _printfEsc,a\b$(\t)c$(\n)d%e%%f),a\\b\tc\nd%e%%f)


# _escArg

$(call _expectEQ,$(call _escArg,(a,b)),$$[a$$;b$$])


# Catch & re-enable fatal errors

error0 := $(value _error)
restoreError = $(eval _error = $(error0))
logError = $(eval *errors* := $$(*errors*)$$(if $$(*errors*),:)$$1)
trapError = $(eval *errors* :=)$(eval _error = $$(logError))

$(trapError)
$(call _error,FAIL$$$])
$(call _error,FAIL2)
$(restoreError)
$(call _expectEQ,$(error0),$(value _error))
$(call _expectEQ,$(*errors*),FAIL$$$]:FAIL2)

# $(call expectError,STR) : assert STR appears in *errors*
expectError = $(if $(findstring $1,$(*errors*)),,$(error Did not find: $(_qv)$(\n)in *errors*: $(call _qv,$(*errors*))))


# $(call $(trapEQ),A,B)
#
#  Like _expectEQ, except that A & B are evaluated while _error is trapped,
#  so errors are accumulated in *errors*.
#
trapEQ = $(trapError)finishTrapEQ
finishTrapEQ = $(restoreError)$(call _expectEQ,$1,$2)

$(call _expectEQ,a,a)
$(call $(trapEQ),$(call _error,FOO),$(call _error,BAR))
$(call _expectEQ,$(*errors*),FOO:BAR)
$(call _expectEQ,$(error0),$(value _error))


# Reference Expansion

ev1 = o1 @ev2 o4
ev2 = o2 o3
ev3 = #empty
# simple reference
$(call _expectEQ,$(call _expand,a @ev1 b),a o1 o2 o3 o4 b)
# map reference: C@V
$(call _expectEQ,$(call _expand,a C@ev1 D@ev3 b),a C(o1) C(o2) C(o3) C(o4)  b)
# chained map reference: C@D@V
$(call _expectEQ,$(call _expand,C@D@ev2),C(D(o2)) C(D(o3)))


# get
#
# Test only for coverage; more granular tests are in *.scm.

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


# _goalID

Alias(alias1).in = x
Alias(alias2).command = y
Alias(alias3).in = x3
Alias(alias3).command = y3

_aliases := alias1 alias2
$(call _expectEQ,$(call _goalID,alias1),Alias(alias1))
$(call _expectEQ,$(call _goalID,@asdf),_Goal(@asdf))
$(call _expectEQ,$(call _goalID,as(df)),_Goal(as(df)))
$(call _expectEQ,$(call _goalID,asdf),)


# _depsOf, _rollup, _rollupEx

R(a).needs = R(b) R(c) x y z
R(b).needs = R(c) x y z
R(c).needs = R(d)
R(d).needs = R(e)
R(e).needs = 

$(call _expectEQ,\
  $(call _depsOf,R(a)),\
  R(b) R(c) R(d) R(e))
$(call _expectEQ,\
   $(call _rollup,R(a)),\
   R(a) R(b) R(c) R(d) R(e))
$(call _expectEQ,\
  $(strip $(call _rollupEx,R(a))),\
  R(a) R(b) R(c) R(d) R(e))
$(call _expectEQ,\
  $(strip $(call _rollupEx,R(a),R(d))),\
  R(a) R(b) R(c))


_R(d)_needs = R(x)
R(x).needs=

$(call _expectEQ,\
  $(strip $(call _rollupEx,R(a),R(d))),\
  R(a) R(b) R(c) R(x))


# Help

C.inherit = Builder
C.x = <$(_argText)>
C.x.y = :$(_argText):

$(call _expectEQ,$(call _goalType,C(I).P),Property)
$(call _expectEQ,$(call _goalType,C(I)),Instance)
$(call _expectEQ,$(call _goalType,C(c(I).p)),Instance)
$(call _expectEQ,$(call _goalType,@Var),Indirect)
$(call _expectEQ,$(call _goalType,C@Var),Indirect)
$(call _expectEQ,$(call _goalType,C(@Var)),Instance)
$(call _expectEQ,$(call _goalType,C(c(@var))),Instance)
$(call _expectEQ,$(call _goalType,alias1),Alias)
$(call _expectEQ,$(call _goalType,alias2),Alias)
$(call _expectEQ,$(call _goalType,abc),Other)


# _once

O1 = 1
o1_compute = $(O1)
o1 = $(call _once,o1_compute)

$(call _expectEQ,$(o1),1)
O1 = 2
$(call _expectEQ,$(o1),1)


# _args

$(call _expectEQ,1,$(call true,_argError)) # minion.mk should supply one
_argError = $(subst `$[,<[>,$(subst `$],<]>,$1))

$(call _expectEQ,$(call _argHash,a$;x:1),:a x:1)
$(call _expectEQ,$(call _argHash,a$]),:a<]>)

Foo.inherit = Builder
Foo.args = $(_args)
Foo.argX = $(call _namedArgs,X)

$(call _expectEQ,$(call _argHash,C(A)$;B$;X:Y),:C(A) :B X:Y)
$(call _expectEQ,$(call get,args,Foo(C(A)$;B$;X:Y)),C(A) B)
$(call _expectEQ,$(call get,argX,Foo(C(A)$;B$;X:Y)),Y)


# _outBasis

# file
$(call _expectEQ,$(call _outBasis,C,a.c,,a.c,a.c),C.c/a.c)
# indirection
$(call _expectEQ,$(call _outBasis,P,C@D@d/v,,,C@D@d/v),P_C@_D@/d/v)
# complex
$(call _expectEQ,\
  $(call _outBasis,P,C(d/a.c)$;o:3,%,.out/C.c/d/a.o,C(d/a.c)),\
  P_@1$;o@C3_C.c/d/a.o)

# .out

P.inherit = Builder
P.outExt = %.p

$(call _expectEQ,$(call get,outBasis,P(a.o)),.out/P/a.o)
$(call _expectEQ,$(call get,outExt,P(a.o)),%.p)
$(call _expectEQ,$(call get,outName,P(a.o)),a.o.p)
$(call _expectEQ,$(call get,outDir,P(a.o)),.out/P/)
$(call _expectEQ,$(call get,out,P(a.o)),.out/P/a.o.p)

p1 = a.c
$(call _expectEQ,$(call get,out,CExe(@p1)),.out/CExe_@/p1)

$(call _expectEQ,$(call get,out,CC(@p1)),.out/CC_@/p1.o)

# Inference

Dup.inherit = Builder
Dup.out = dup/$(_argText)

C.outExt = .o

Inf.inherit = Builder
Inf.inferClasses = C.c C.cpp
Inf(x).in = a.c b.cpp Dup(c.c) d.o

$(call _expectEQ,$(call get,in,Inf(x)),a.c b.cpp Dup(c.c) d.o)
$(call _expectEQ,\
  $(call get,inPairs,Inf(x)),\
  C(a.c)$$.out/C.c/a.o C(b.cpp)$$.out/C.cpp/b.o C(Dup(c.c))$$.out/C.c_/dup/c.o d.o)

# _recipe

$(call _expectEQ,$(call _recipe,$(\n)a$(\n)),$(\t)a$(\n))

# Validation value logic & _vvEnc

define vvEncEval
_dv = $(call _vvEnc,$1,OUT)
ifeq "$$(_dv)" "$(call _vvEnc,$2,OUT)"
  vvIsOK=1
else
  vvIsOK=
endif
endef

vvEQ? = $(eval $(call vvEncEval,$1,$2))$(vvIsOK)
vvOK? = $(call vvEQ?,$1,$1)

$(call _expectEQ,1,$(call vvOK?,abc))
# Trailing "\" can cause problems if not guarded
$(call _expectEQ,1,$(call vvOK?,abc\))
# Leading and trailing spaces; validate assumptions about Make syntax
$(call _expectEQ,1,$(call vvOK?, \# \ \\ $$a $(\t)$(\n) x ))


# _defer

Defer.inherit = Builder
Defer.command = true $(call _lazy,$$($(_argText)))
Defer.vvFile =

define DeferRule
.out/Defer/a : a   | 
	@echo '#-> Defer(a)'
	@mkdir -p .out/Defer/
	true $(a)


endef

$(call _expectEQ,$(call get,rule,Defer(a)),$(value DeferRule))

# _group

$(call _expectEQ,\
  $(call _group,a b c d e,3),\
  a$(\n)b$(\n)c d$(\n)e$(\n))

$(call _expectEQ,\
  $(foreach g,$(call _group,1 2 3 4 5 6 7 8,3),$(strip $g)|),\
  1 2 3| 4 5 6| 7 8|)


# Built-in classes

WVAR = test

define WWrule
.out/Write/WVAR :    | 
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

$(info $(MINION) ok)
