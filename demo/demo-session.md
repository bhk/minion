# Example Walk-through


## Introduction

Here is an actual command line session that introduces Minion
functionality.  You can follow along typing the commands yourself in the
`demo` subdirectory of the project.

We begin with a minimal makefile:

    $ cp Makefile1 Makefile
    $ cat Makefile

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

    $ make 'CC(hello.c)'
    $ make 'CExe(CC(hello.c))'
    $ make 'Run(CExe(CC(hello.c)))'


## Inference

Some classes have the ability to *infer* intermediate build steps, based on
the extension of the input file (or files).  For example, if we provide a
".c" file as an argument to `CExe`, it knows how to generate the
intermediate ".o" artifact.

    $ make 'CExe(hello.c)'

This command linked the program, but did not rebuild `hello.o`.  This is
because we have already built the inferred dependency, `CC(hello.c)`.  Doing
nothing, whenever possible, is what a build system is all about.

We can demonstrate that everything will get re-built, if necessary, by
re-issuing this command after invoking `make clean`.  The `clean` target is
defined by Minion, and it removes the "output directory", which, by default,
contains all generated artifacts.

    $ make clean; make 'CExe(hello.c)'

Likewise, `Run` can also infer a `CExe` instance (which in turn will infer
a `CC` instance):

    $ make clean; make 'Run(hello.c)'


## Phony Targets

A `Run` instance writes to `stdout` and does not generate an output file.
It does not make sense to talk about whether its output file needs to be
"rebuilt", because there is no output file.  Targets like this, that exist
for side effects only, are called phony targets.  They are always executed
whenever they are named as a goal, or as a prerequisite of a target named as
a goal, and so on.

    $ make 'Run(hello.c)'

A class named `Exec` also runs a program, but it captures its output in a
file, so its targets are *not* phony.

    $ make 'Exec(hello.c)'

Using `Exec` is a way to run unit tests.  The existence of the output file
is evidence that the unit test passed (the program exited without an error
code).  If we want to view the output, we can use `Print`, a class that
generates a phony target that writes its input to `stdout`:

    $ make 'Print(hello.c)'
    $ make 'Print(Exec(hello.c))'


## Help

When the goal `help` appears on the command line, Minion will describe all
of the other goals on the command line, instead of building them.  This
gives us visibility into how things are being interpreted, and how they map
to underlying Make primitives.

    $ make help 'Run(hello.c)'
    $ make help 'Exec(hello.c)'


## Indirections

An *indirection* is a way of referencing the contents of a variable.  These
can be used in contexts where input files or prerequisites are specified for
Minion instances.  There are two forms of indirections.  The first is called
a simple indirection, written `@VARIABLE`.  It represents all of the files
or instances named in the variable.

    $ make 'CExe(@sources)' sources='hello.c empty.c'

The other form is called a mapped indirection, written `CLASS@VARIABLE`.
This references a set of instances which are obtained by applying the class
to each target identified in the variable.

    $ make help Run@sources sources='hello.c binsort.c'
    $ make Run@sources sources='hello.c binsort.c'


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

    $ cp Makefile2 Makefile
    $ cat Makefile
    $ make deploy

If no goals are provided on the command line, Minion attempts to build the
alias or target named `default`, so these commands do the same thing:

    $ make
    $ make default

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

    $ make 'CC(hello.c).objFlags=-Os'

Observe how the resulting `gcc` command line differs from that of the
earlier `CC(hello.c)`.  [By the way, also note that Minion knew to
re-compile the object file, even when no input files had changed.  The
previous build result became invalid when the command line changed.  This
fine-grained dependency tracking means that when using Minion you almost
never need to `make clean`, even after you have edited your makefile.]

We can make this change apply more widely:

    $ make CC.objFlags=-Os

So what's going on here?

Each instance consists of a set of properties.  Properties definitions can
be given for a specific instance, or for a class.  There is a notion of
*inheritance*, similar to that of some object-oriented languages (hence the
term "instance"), but in Minion there is no mutable state associated with
instances.

We can best illustrate the basic principles of property evaluation with a
simple example that avoids the complexities of `CC` and other Minion rules.

    $ cat MakefileP

This makefile includes various definitions for the properties `x`, `y`, and
`z`, attached to different classes and instances.  We can use Minion's
`help` facility to interactively explore property definitions and their
computed values.

    $ make -f MakefileP help 'C1(a).x'

Here, the definition for `x` came from a matching instance-specific
definition, which takes precedence over all other definitions.

If there is no matching instance-specific definition, the `CLASS.PROP`
definition is chosen:

    $ make -f MakefileP help 'C1(b).x'

When there is no matching `CLASS.PROP` definition, `CLASS.inherit` will be
consulted, and Minion will look for definitions associated with those
classes, in the order they are listed.  (Note that `inherit` in
`CLASS.inherit` is not a property name; this is just the way to specify
inheritance.)

    $ make -f MakefileP help 'C2(b).x'

Property definitions can refer to other properties using the `{NAME}`
syntax:

    $ make -f MakefileP help 'C2(b).value'

When a definition includes `{inherit}`, it is replaced with the property
value that would have been inherited.  That is, Minion looks for the *next*
definition for the current property in the inheritance sequence, and
evaluates it.

    $ make -f MakefileP help 'C3(b).z'

This can be used to, for example, provide a property definition that simply
adds a flag to a list of flags, without discarding all of the
previously-inherited values.

Returning to our `CC(hello.c)` instance, we can look at some of the
properties that determine how it works.

The `command` property gives the command that will be executed to build the
target file.

    $ make help 'CC(hello.c).command'

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

    $ cp Makefile3 Makefile; diff Makefile2 Makefile3

A variable assignment of the form `CLASS.inherit` specifies the base class
from which `CLASS` inherits.  (It resembles a property definition, but
`inherit` is a special keyword, not a property.)

This makefile defines a class named `Sizes`, which inherits from `Phony`,
which is a base class for phony targets.  Phony targets must be identified
to Make using the special target `.PHONY: ...`, and since they have no
output file, the recipe should not bother creating an output directory for
them.  The `Phony` class takes care of all of this, so our subclass needs
only to define `command`.

    $ make 'Sizes(CC(hello.c),CCg(hello.c))'

This makefile also defines a class named `CCg`, and defines `CCg.objFlags`
using `{inherit}` so that it will extend, not replace, the set of flags it
inherits.

    $ make help 'CCg(hello.c).objFlags'


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

    $ cp Makefile4 Makefile
    $ cat Makefile
    $ make V=debug help 'CC(hello.c).objFlags'

Finally, we want to be able to build multiple variants with a single
invocation.  Minion provides a built-in class, `Variants(TARGET)`, that
builds a number of variants of the target `TARGET`.  The `all` property
gives the list of variants, so assigning `Variants.all` will establish a
default set of variants for all instances of `Variants`.

The variable `Variants.all` is also used to provide a default for `V`: it
defaults to the first word in `Variants.all`.

    $ make sizes           # sizes for the default (first) variant "debug"
    $ make sizes V=fast    # sizes for the "fast" variant
    $ make all-sizes       # sizes for *all* variants


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
