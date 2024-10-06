# Example Walk-through


## Introduction

Here is an actual command line session that introduces Minion
functionality.  You can follow along typing the commands yourself in the
`demo` subdirectory of the project.

We begin with a minimal makefile:

```console
$ cp Makefile1 Makefile

```
```console
$ cat Makefile
include ../minion.mk

```

This makefile doesn't describe anything to be built, but it does invoke
Minion, so when we type `make` in this directory, Minion will process the
goals.  A *goal* is a target name that is listed on the command line.  Goals
determine what Make actually does when it is invoked.


## Instances

The salient feature of Minion is instances.  An instance is a description of
a build step.  Instances can be provided as goals or as inputs to other
build steps.

An instance is written `CLASS(ARGS)`.  `ARGS` is a comma-delimited list of
arguments, each of which is typically the name of an input to the build
step.  `CLASS` is the name of a class that is defined by Minion or your
makefile.  To get started, let's use some classes that are built into
Minion:

```console
$ make 'CC(hello.c)'
#-> CC(hello.c)
gcc -c -o .out/CC.c/hello.o hello.c -std=c99 -Wall -Werror -O2   -MMD -MP -MF .out/CC.c/hello.o.d

```
```console
$ make 'CExe(CC(hello.c))'
#-> CExe(CC(hello.c))
gcc -o .out/CExe.o_CC.c/hello .out/CC.c/hello.o  

```
```console
$ make 'Run(CExe(CC(hello.c)))'
#-> Run(CExe(CC(hello.c)))
.out/CExe.o_CC.c/hello  
Hello world.

```


## Inference

Some classes have the ability to *infer* intermediate build steps, based on
the extension of the input file (or files).  For example, if we provide a
".c" file as an argument to `CExe`, it knows how to generate the
intermediate ".o" artifact.

```console
$ make 'CExe(hello.c)'
#-> CExe(hello.c)
gcc -o .out/CExe.c/hello .out/CC.c/hello.o  

```

This command linked the program, but did not rebuild `hello.o`.  This is
because we have already built the inferred dependency, `CC(hello.c)`.  Doing
nothing, whenever possible, is what a build system is all about.

We can demonstrate that everything will get re-built, if necessary, by
re-issuing this command after invoking `make clean`.  The `clean` target is
defined by Minion, and it removes the "output directory", which, by default,
contains all generated artifacts.

```console
$ make clean; make 'CExe(hello.c)'
rm -rf .out/
#-> CC(hello.c)
gcc -c -o .out/CC.c/hello.o hello.c -std=c99 -Wall -Werror -O2   -MMD -MP -MF .out/CC.c/hello.o.d
#-> CExe(hello.c)
gcc -o .out/CExe.c/hello .out/CC.c/hello.o  

```

Likewise, `Run` can also infer a `CExe` instance (which in turn will infer
a `CC` instance):

```console
$ make clean; make 'Run(hello.c)'
rm -rf .out/
#-> CC(hello.c)
gcc -c -o .out/CC.c/hello.o hello.c -std=c99 -Wall -Werror -O2   -MMD -MP -MF .out/CC.c/hello.o.d
#-> CExe(hello.c)
gcc -o .out/CExe.c/hello .out/CC.c/hello.o  
#-> Run(hello.c)
.out/CExe.c/hello  
Hello world.

```


## Phony Targets

A `Run` instance writes to `stdout` and does not generate an output file.
It does not make sense to talk about whether its output file needs to be
"rebuilt", because there is no output file.  Targets like this, that exist
for side effects only, are called phony targets.  They are always executed
whenever they are named as a goal, or as a prerequisite of a target named as
a goal, and so on.

```console
$ make 'Run(hello.c)'
#-> Run(hello.c)
.out/CExe.c/hello  
Hello world.

```

A class named `Exec` also runs a program, but it captures its output in a
file, so its targets are *not* phony.

```console
$ make 'Exec(hello.c)'
#-> Exec(hello.c)
(  .out/CExe.c/hello   ) > .out/Exec.c/hello.out || ( rm -f .out/Exec.c/hello.out; false )

```

Using `Exec` is a way to run unit tests.  The existence of the output file
is evidence that the unit test passed (the program exited without an error
code).  If we want to view the output, we can use `Print`, a class that
generates a phony target that writes its input to `stdout`:

```console
$ make 'Print(hello.c)'
#include <stdio.h>

int main() {
   printf("Hello world.\n");
}

```
```console
$ make 'Print(Exec(hello.c))'
Hello world.

```


## Help

When the goal `help` appears on the command line, Minion will describe all
of the other goals on the command line, instead of building them.  This
gives us visibility into how things are being interpreted, and how they map
to underlying Make primitives.

```console
$ make help 'Run(hello.c)'
Run(hello.c) is an instance.

{out} = .out/Run.c/hello.out

{command} =  .out/CExe.c/hello  

Direct dependencies: 
   CExe(hello.c)

Indirect dependencies: 
   CC(hello.c)

```
```console
$ make help 'Exec(hello.c)'
Exec(hello.c) is an instance.

{out} = .out/Exec.c/hello.out

{command} = (  .out/CExe.c/hello   ) > .out/Exec.c/hello.out || ( rm -f .out/Exec.c/hello.out; false )

Direct dependencies: 
   CExe(hello.c)

Indirect dependencies: 
   CC(hello.c)

```


## Indirections

An *indirection* is a way of referencing the contents of a variable.  These
can be used in contexts where input files or prerequisites are specified for
Minion instances.  There are two forms of indirections.  The first is called
a simple indirection, written `@VARIABLE`.  It represents all of the files
or instances named in the variable.

```console
$ make 'CExe(@sources)' sources='hello.c empty.c'
#-> CC(empty.c)
gcc -c -o .out/CC.c/empty.o empty.c -std=c99 -Wall -Werror -O2   -MMD -MP -MF .out/CC.c/empty.o.d
#-> CExe(@sources)
gcc -o .out/CExe_@/sources .out/CC.c/hello.o .out/CC.c/empty.o  

```

The other form is called a mapped indirection, written `CLASS@VARIABLE`.
This references a set of instances which are obtained by applying the class
to each target identified in the variable.

```console
$ make help Run@sources sources='hello.c binsort.c'
Run@sources is an indirection on the following variable:

   sources = hello.c binsort.c

It expands to the following targets: 
   Run(hello.c)
   Run(binsort.c)

```
```console
$ make Run@sources sources='hello.c binsort.c'
#-> Run(hello.c)
.out/CExe.c/hello  
Hello world.
#-> CC(binsort.c)
gcc -c -o .out/CC.c/binsort.o binsort.c -std=c99 -Wall -Werror -O2   -MMD -MP -MF .out/CC.c/binsort.o.d
#-> CExe(binsort.c)
gcc -o .out/CExe.c/binsort .out/CC.c/binsort.o  
#-> Run(binsort.c)
.out/CExe.c/binsort  
srch(7) = 5
srch(6) = 9
srch(12) = 9
srch(0) = 9

```


## Aliases

So far we haven't added anything to our makefile, so we could only build
things that we explicitly describe on the command line.  A build system
should allow us to describe complex builds in a makefile so they can invoked
with a simple command, like `make` or `make deploy`.  Minion provides
*aliases* for this purpose.  An alias is a name that identifies a phony
target instead of an actual file.

To define an alias, do one of the following (or both):

1. Define a variable named `Alias(NAME).in`.  The value you assign to it
   will be treated as a list of targets to be built when NAME is given as a
   goal.

2. Define a variable named `Alias(NAME).command`.  The value you assign
   to is will be treated as a command to be executed when NAME is given
   as a goal.

This next makefile defines aliases named "default" and "deploy":

```console
$ cp Makefile2 Makefile

```
```console
$ cat Makefile
sources = hello.c binsort.c

Alias(default).in = Exec@sources
Alias(deploy).in = Copy@CExe@sources

include ../minion.mk

```
```console
$ make deploy
#-> Copy(CExe(hello.c))
cp .out/CExe.c/hello .out/Copy/hello
#-> Copy(CExe(binsort.c))
cp .out/CExe.c/binsort .out/Copy/binsort

```

If no goals are provided on the command line, Minion attempts to build the
alias or target named `default`, so these commands do the same thing:

```console
$ make
#-> Exec(binsort.c)
(  .out/CExe.c/binsort   ) > .out/Exec.c/binsort.out || ( rm -f .out/Exec.c/binsort.out; false )

```
```console
$ make default

```

One last note about aliases: alias names are just for use as goals on the
Make command line.  Within a Minion makefile, when specifying targets we use
only instances, source file names, or targets of Make rules.  So if you want
to refer to one alias as a dependency of another alias, use its instance
name: `Alias(NAME)`.  For example:

    Alias(default).in = Alias(exes) Alias(tests)


## Properties and Customization

A build system should make it easy to customize the way build results are
generated, and to define entirely new, unanticipated build steps.  Let's
show a couple of examples, and then dive into how and why they work.

```console
$ make 'CC(hello.c).objFlags=-Os'
#-> CC(hello.c)
gcc -c -o .out/CC.c/hello.o hello.c -std=c99 -Wall -Werror -Os   -MMD -MP -MF .out/CC.c/hello.o.d
#-> CExe(hello.c)
gcc -o .out/CExe.c/hello .out/CC.c/hello.o  
#-> Exec(hello.c)
(  .out/CExe.c/hello   ) > .out/Exec.c/hello.out || ( rm -f .out/Exec.c/hello.out; false )

```

Observe how the resulting `gcc` command line differs from that of the
earlier `CC(hello.c)`.  [By the way, also note that Minion knew to
re-compile the object file, even when no input files had changed.  The
previous build result became invalid when the command line changed.  This
fine-grained dependency tracking means that when using Minion you almost
never need to `make clean`, even after you have edited your makefile.]

We can make this change apply more widely:

```console
$ make CC.objFlags=-Os
#-> CC(binsort.c)
gcc -c -o .out/CC.c/binsort.o binsort.c -std=c99 -Wall -Werror -Os   -MMD -MP -MF .out/CC.c/binsort.o.d
#-> CExe(binsort.c)
gcc -o .out/CExe.c/binsort .out/CC.c/binsort.o  
#-> Exec(binsort.c)
(  .out/CExe.c/binsort   ) > .out/Exec.c/binsort.out || ( rm -f .out/Exec.c/binsort.out; false )

```

So what's going on here?

Each instance consists of a set of properties.  Properties definitions can
be given for a specific instance, or for a class.  There is a notion of
*inheritance*, similar to that of some object-oriented languages (hence the
term "instance"), but in Minion there is no mutable state associated with
instances.

We can best illustrate the basic principles of property evaluation with a
simple example that avoids the complexities of `CC` and other Minion rules.

```console
$ cat MakefileP
C1(a).x = Xa

C1.value = {x} {y} {z}
C1.x = X1
C1.y = Y1
C1.z = Z1

C2.inherit = C1
C2.z = C2

C3.inherit = C2
C3.y = Y3
C3(b).z = {inherit}b

Extra.z = ZZZ

C4.inherit = Extra C3

include ../minion.mk

```

This makefile includes various definitions for the properties `x`, `y`, and
`z`, attached to different classes and instances.  We can use Minion's
`help` facility to interactively explore property definitions and their
computed values.

```console
$ make -f MakefileP help 'C1(a).x'
C1(a) inherits from: C1

{x} is defined by:

   C1(a).x = Xa

Its value is: 'Xa'


```

Here, the definition for `x` came from a matching instance-specific
definition, which takes precedence over all other definitions.

If there is no matching instance-specific definition, the `CLASS.PROP`
definition is chosen:

```console
$ make -f MakefileP help 'C1(b).x'
C1(b) inherits from: C1

{x} is defined by:

   C1.x = X1

Its value is: 'X1'


```

When there is no matching `CLASS.PROP` definition, `CLASS.inherit` will be
consulted, and Minion will look for definitions associated with those
classes, in the order they are listed.  (Note that `inherit` in
`CLASS.inherit` is not a property name; this is just the way to specify
inheritance.)

```console
$ make -f MakefileP help 'C2(b).x'
C2(b) inherits from: C2 C1

{x} is defined by:

   C1.x = X1

Its value is: 'X1'


```

Property definitions can refer to other properties using the `{NAME}`
syntax:

```console
$ make -f MakefileP help 'C2(b).value'
C2(b) inherits from: C2 C1

{value} is defined by:

   C1.value = {x} {y} {z}

Its value is: 'X1 Y1 C2'


```

When a definition includes `{inherit}`, it is replaced with the property
value that would have been inherited.  That is, Minion looks for the *next*
definition for the current property in the inheritance sequence, and
evaluates it.

```console
$ make -f MakefileP help 'C3(b).z'
C3(b) inherits from: C3 C2 C1

{z} is defined by:

   C3(b).z = {inherit}b

...wherein {inherit} references:

   C2.z = C2

Its value is: 'C2b'


```

This can be used to, for example, provide a property definition that simply
adds a flag to a list of flags, without discarding all of the
previously-inherited values.

Returning to our `CC(hello.c)` instance, we can look at some of the
properties that determine how it works.

The `command` property gives the command that will be executed to build the
target file.

```console
$ make help 'CC(hello.c).command'
CC(hello.c) inherits from: CC _CC CCBase _CCBase Builder

{command} is defined by:

   _CCBase.command = {compiler} -c -o {@} {<} {options} -MMD -MP -MF {@}.d

Its value is: 'gcc -c -o .out/CC.c/hello.o hello.c -std=c99 -Wall -Werror -O2   -MMD -MP -MF .out/CC.c/hello.o.d'


```

Here we see the computed value and its definition, which is attached to a
base class called `_Compile`.  We can also see the classes from which this
instance inherits properties, in order of precedence, so we can consider
which classes to which we might attach new property definitions.

The `@` and `<` properties mimic the `$@` and `$<` variables available in
Make recipes, and there is also a `^` property analogous to `$^`.  We can
see that the `_Compile.command` definition concerns itself with specifying
the input files, output files, and implied dependencies.  It refers to a
property named `flags` for command-line options that address other concerns.

We can now see how the earlier command that set `CC(hello.c).objFlags=-Os`
defined an instance-specific property, so it only affected the command line
for one object file, whereas the command that set `CC.objFlags` provided a
definition inherited by both `CC` instances.

### User Classes

An important note about overriding class properties: `CC` is a *user class*,
intended for customization by user makefiles.  Minion does not attach any
properties *directly* to user classes; it just provides a default
inheritance, and that, too, can be overridden by the user makefile.  User
classes are listed in `minion.mk`, and you can easily identify a user class
because it will inherit from an internal class that has the same name except
for a prefixed underscore (`_`).

Directly re-defining properties of non-user classes in Minion is not
supported.  Instead, define your own sub-classes.


## Custom Classes

```console
$ cp Makefile3 Makefile; diff Makefile2 Makefile3
5a6,13
> CC.langFlags = {inherit} -Wextra
> 
> CCg.inherit = CC
> CCg.objFlags = -g
> 
> Sizes.inherit = Phony
> Sizes.command = wc -c {^}
> 

```

A variable assignment of the form `CLASS.inherit` specifies the base class
from which `CLASS` inherits.  (It resembles a property definition, but
`inherit` is a special keyword, not a property.)

This makefile defines a class named `Sizes`, which inherits from `Phony`,
which is a base class for phony targets.  Phony targets must be identified
to Make using the special target `.PHONY: ...`, and since they have no
output file, the recipe should not bother creating an output directory for
them.  The `Phony` class takes care of all of this, so our subclass needs
only to define `command`.

```console
$ make 'Sizes(CC(hello.c),CCg(hello.c))'
#-> CC(hello.c)
gcc -c -o .out/CC.c/hello.o hello.c -std=c99 -Wall -Werror -O2   -MMD -MP -MF .out/CC.c/hello.o.d
#-> CCg(hello.c)
gcc -c -o .out/CCg.c/hello.o hello.c -std=c99 -Wall -Werror -g   -MMD -MP -MF .out/CCg.c/hello.o.d
wc -c .out/CC.c/hello.o .out/CCg.c/hello.o
     744 .out/CC.c/hello.o
    2160 .out/CCg.c/hello.o
    2904 total

```

This makefile also defines a class named `CCg`, and defines `CCg.objFlags`
using `{inherit}` so that it will extend, not replace, the set of flags it
inherits.

```console
$ make help 'CCg(hello.c).objFlags'
CCg(hello.c) inherits from: CCg CC _CC CCBase _CCBase Builder

{objFlags} is defined by:

   CCg.objFlags = -g

Its value is: '-g'


```


## Variants

We can build different *variants* of the project described by our makefile.
Variants are separate instantiations of our build that will have a similar
overall structure, but may differ from each other in various ways.  For
example, we may have "release" and "debug" variants, or "ARM" and "Intel"
variants of a C project.

We have shown how typing `make CC.objFlags=-g` and then later `make
CC.objFlags=-O3` could be used to achieve different builds.  With this
approach, however, each time we "switch" between the two builds, all
affected files will have to be recompiled.

Instead, we want these variants to exist side-by-side and not interfere with
each other, so we can retain all the advantages of incremental builds.  We
achieve that by doing the following:

  * Use the variable `V` to identify a variant name, so that `make
    V=<name>` can be used to build a specific variant.

  * Define properties in a way that depends on `$V`.

  * Incorporate `$V` into the output directory.  Minion does this by default
    when `V` is assigned a non-empty value.

When defining variant-dependent properties, we could use Make's functions:

    CC.objFlags = $(if $(filter debug,$V),{dbgFlags},{optFlags})
    CC.dbgFlags = ...
    CC.optFlags = ...

Alternatively, we could leverage Minion's property inheritance and define
classes for each variant by incorporating `$V` into the class name.  That
would look like this:

    CC.inherit = CC-$V _CC

    CC-debug.objFlags = -g
    CC-fast.objFlags = -O3
    CC-small.objFlags = -Os

[Note that these classes do not appear last in the list of parents of `CC`,
so they do not have to inherit from `Builder` or define the essential
properties that it defines.  Instead, they are concerned only with
purpose-specific customizations.  We call classes like this **mixins**.]

The following makefile uses this approach.

```console
$ cp Makefile4 Makefile

```
```console
$ cat Makefile
Variants.all = debug fast small

Alias(sizes).in = Sizes(CExe@sources)
Alias(all-sizes).in = Variants(Alias(sizes))
Alias(default).in = Alias(sizes)

sources = hello.c binsort.c

CC.inherit = CC-$V _CC

CC-debug.objFlags = -g
CC-fast.objFlags = -O3
CC-small.objFlags = -Os

Sizes.inherit = Phony
Sizes.command = wc -c {^}

include ../minion.mk

```
```console
$ make V=debug help 'CC(hello.c).objFlags'
CC(hello.c) inherits from: CC CC-debug _CC CCBase _CCBase Builder

{objFlags} is defined by:

   CC-debug.objFlags = -g

Its value is: '-g'


```

Finally, we want to be able to build multiple variants with a single
invocation.  Minion provides a built-in class, `Variants(TARGET)`, that
builds a number of variants of the target `TARGET`.  The `all` property
gives the list of variants, so assigning `Variants.all` will establish a
default set of variants for all instances of `Variants`.

The variable `Variants.all` is also used to provide a default for `V`: it
defaults to the first word in `Variants.all`.

```console
$ make sizes           # sizes for the default (first) variant "debug"
#-> CC(hello.c)
gcc -c -o .out/debug/CC.c/hello.o hello.c -std=c99 -Wall -Werror -g   -MMD -MP -MF .out/debug/CC.c/hello.o.d
#-> CExe(hello.c)
gcc -o .out/debug/CExe.c/hello .out/debug/CC.c/hello.o  
#-> CC(binsort.c)
gcc -c -o .out/debug/CC.c/binsort.o binsort.c -std=c99 -Wall -Werror -g   -MMD -MP -MF .out/debug/CC.c/binsort.o.d
#-> CExe(binsort.c)
gcc -o .out/debug/CExe.c/binsort .out/debug/CC.c/binsort.o  
wc -c .out/debug/CExe.c/hello .out/debug/CExe.c/binsort
   33672 .out/debug/CExe.c/hello
   33944 .out/debug/CExe.c/binsort
   67616 total

```
```console
$ make sizes V=fast    # sizes for the "fast" variant
#-> CC(hello.c)
gcc -c -o .out/fast/CC.c/hello.o hello.c -std=c99 -Wall -Werror -O3   -MMD -MP -MF .out/fast/CC.c/hello.o.d
#-> CExe(hello.c)
gcc -o .out/fast/CExe.c/hello .out/fast/CC.c/hello.o  
#-> CC(binsort.c)
gcc -c -o .out/fast/CC.c/binsort.o binsort.c -std=c99 -Wall -Werror -O3   -MMD -MP -MF .out/fast/CC.c/binsort.o.d
#-> CExe(binsort.c)
gcc -o .out/fast/CExe.c/binsort .out/fast/CC.c/binsort.o  
wc -c .out/fast/CExe.c/hello .out/fast/CExe.c/binsort
   33432 .out/fast/CExe.c/hello
   33480 .out/fast/CExe.c/binsort
   66912 total

```
```console
$ make all-sizes       # sizes for *all* variants
wc -c .out/debug/CExe.c/hello .out/debug/CExe.c/binsort
   33672 .out/debug/CExe.c/hello
   33944 .out/debug/CExe.c/binsort
   67616 total
wc -c .out/fast/CExe.c/hello .out/fast/CExe.c/binsort
   33432 .out/fast/CExe.c/hello
   33480 .out/fast/CExe.c/binsort
   66912 total
#-> CC(hello.c)
gcc -c -o .out/small/CC.c/hello.o hello.c -std=c99 -Wall -Werror -Os   -MMD -MP -MF .out/small/CC.c/hello.o.d
#-> CExe(hello.c)
gcc -o .out/small/CExe.c/hello .out/small/CC.c/hello.o  
#-> CC(binsort.c)
gcc -c -o .out/small/CC.c/binsort.o binsort.c -std=c99 -Wall -Werror -Os   -MMD -MP -MF .out/small/CC.c/binsort.o.d
#-> CExe(binsort.c)
gcc -o .out/small/CExe.c/binsort .out/small/CC.c/binsort.o  
wc -c .out/small/CExe.c/hello .out/small/CExe.c/binsort
   33432 .out/small/CExe.c/hello
   33480 .out/small/CExe.c/binsort
   66912 total

```


## Recap

To summarize the key concepts in Minion:

 - *Instances* are function-like descriptions of build products.  They can
   be given as Make command line goals, and named as inputs to other
   instances.  They take the form `CLASS(ARGUMENTS)`.

 - *Indirections* are ways to reference Make variables that hold lists of
   other targets.  They can be used as arguments to instances, or in the
   value of an `in` property, or on the command line.

 - *Aliases* are short names that can be specified as goals on the command
   line.  An alias can identify a set of other targets to be built, or a
   command to be executed, or both.

 - *Properties* dictate how instances behave.  Properties definitions are
   associated with classes or instances, and classes may inherit property
   definitions from other classes.  Properties are defined using Make
   variables whose names identify the property, class, and perhaps instance
   to which they apply.  Property definitions can use Make variables and
   functions, and they can refer to other properties using the `{NAME}`
   syntax.

 - To support multiple variants, list them in `Variants.all` putting the
   default variant first.  Use `make V=VARIANT TARGET` to build a specific
   variant of a target, and use `make 'Variants(TARGET)'` to build all
   variants of a target.

