# Notes

## Todo

 - add {depsCommand} and {depsFile}
   irk's ESBuild is an example.  Common use case for implied deps.
   depsCommand does not influence the output file (not incl. in vvValue)

 - $(call _use,EXPR) : Evaluate $(EXPR) and add the value to the "validity
   value" for the cached makefile (saved in the cached makefile itself).

     $(eval useHash += $(filter-out useHash,<KEY:VALUE>))


## Design Notes

### Special characters in filenames

We could support filenames that contain spaces and other characters that are
usually difficult to handle in Make.  It would look like this:

Target lists could contain quoted substrings, and `_expand` would convert
them to a word-encoded form (`!` -> `!1`, ` ` -> `!0`, `\t` -> `!+`, ...).

     sources = "Hello World!.c" bar.c
     $(call _expand,*sources)  -->  Hello!0World!1.c bar.c
     {in}                      -->  Hello!0World!1.c bar.c
     {^}                       -->  'Hello World!.c' bar.c

The shorthand properties, {@}, {^} and {<}, would encode their values for
inclusion on shell command lines.  Presence of "!" means that quoting is
necessary; other file names remain unquoted.

Where file names are provided to Make (in rules), Minion would encode the
names properly for Make.  E.g.: `$(call _mkEnc,{out} : {prereqs} ...)`
In Make targets & pre-requisistes, we must backslash-escape:

      \s \t : = % * [ ] ?

In Make v3.81, wildcard character escaping does not work.

Syntax would be amended:

    Name := ( NameChar | '"' QChar+ '"' )+

For `~`, we might want both the shell/Make meaning and the literal form.
E.g.: "~/\~" --> `~/!T`.  (Is there a way to escape for Make?)

Problems:

 * Other Make limitations

    `$(wildcard ...)` won't work.

    Using `dir`, `basename`, etc., on `{@}` et al will not work reliably.
    However, they can be used with {out}, {inFiles}, etc., since they are
    word-encoded; the user would have to explicitly shell-encode the
    results.

 * Assigning instance properties

     define minionDefs
       C("hello world.c").flags = ...
       ...
     endef

 * Pretty-printing instance names

       C!lA!r          --> "C(A)"
       P(C!ra!0b.c!r)  --> P("C(a b.c)")
       P(C(a!0b.c))    --> P(C("a b.c"))
       C(x!cy,a!Cz)    --> C("x,y","a=z")

 * Command-line goal processing

       $ make 'CC("a b.c")'  # 1 arg, 1 goal, 2 words in MAKECMDGOALS


### Rewrites

Can we define a class in terms of another?  Say we want to define `Foo(A)`
as `Bar(A,arg=X)`.  To avoid conflicts, these instance names will need to
have different output files, which means that `Foo(A)` will place the result
at a different location from `Bar(A,arg=X)`, or copy it.

    Foo.inherit = Rewrite
    Foo.in = Bar($(_arg1),arg=X)

However, here `Foo` is not a sub-class of `Bar`, so properties attached to
instances or subclasses of `Foo` will not affect `Bar`.  `Foo` will have to
expose its own interface for extension, which will probably be limited.


### make C(A).P

Instead of a special syntax, use a custom class: PrintProp(C(A).P) (to
echo to stdout) or Prop(C(A).P) (to write to file).

    Prop.inherit = Write
    Prop.data = $(call get,$(_propArgProp),$(_propArgID))


### Variable Namespace Pollution

Class names to be avoided:

    $ echo '$(info $(sort $(patsubst %.,%,$(filter %.,$(subst .,. ,$(.VARIABLES))))))a:;@#' | make -f /dev/stdin
    COMPILE LEX LINK LINT PREPROCESS YACC


### Aliases in Target Lists

Currently "IDs" consist only of instances and "plain" targets (source file
names, or names of phony targets defined by a legacy Make rule).  A "target
list" may contain IDs and indirections (which expand to IDs).  Neither may
contain a bare alias name (e.g. "default", rather than "Alias(default)").
Alias names appear only in goals.

To summarize:

    goals, cache         PLAIN | C(A) | *VAR | ALIAS   (user-facing)
    in, up, oo           PLAIN | C(A) | *VAR           (user-facing)
    get, needs, rollup   PLAIN | C(A)
    out, <, ^, up^       PLAIN                         (user-facing)

The following change would simplify documentation:

    goals, cache, in, ...  PLAIN | C(A) | *VAR | ALIAS   (user-facing)
    get, needs, rollup     PLAIN | C(A)
    out, <, ^, up^         PLAIN                         (user-facing)

[If we were to include ALIAS values in the middle category, then we have
the problem of duplicates due to, uh, "aliasing" of Alias(X) and X.]

This involves (only) a change to `_expand`, which is called many times,
and on occasions when order must be preserved, so performance is a
concern.  Some benchmarking in a large project is in order.  Performance
observations so far:

  * The argument to _expand is often empty (~46%).
  * When not empty, it usually has one element. (~42%)
  * Usually it has no "*" and no alias name, and can return its input.

    (define (_expand names)
      (if names
        (if (or (findstring "@" names)
                (filter _aliases names))
          (call _ex,names) ;; $(_ex)
          names)))


### "Compress" recipe?

We could post-process the recipe to take advantage of $@, $(@D), $<, $^,
$(word 2,$^), ...  [$(@D) fails for files with spaces...]

Or we could directly emit $(@D) for mkdir command, $@ for {@}, $< for {<}
(when non-empty)

Also: we could use a temporary variable to reduce repetition of the target
name within `rule` (in the Make rule, .PHONY)


### More optimization possibilities

 * Separate the cache into "NAME.ids" and "NAME.mk".  NAME.ids
   assigns `_cachedIDs`, and NAME.mk has everything else.  NAME.mk
   is built as a side effect of building NAME.ids.  NAME.ids is
   included when we use the cache, and NAME.mk is used when-AND-IF
   _rollups encounters a cached ID.

   This avoids the time spent loading the cached makefile (and the dep and
   vv files) (maybe 100ms in med-sized project), when (A) restart will occur
   due to stale cache, (B) the goals are non-trivial yet are entirely
   outside the cache.

 * Allow instances to easily select "lazy" recipes, so that their command
   will be evaluated only if the target is stale. However, this provides no
   savings when vv includes {command}.  The only *actual* case right now is
   Makefile[minionCache], which does this on its own.  And Makefile would
   need a way to convert lazy rules into non-lazy:

      ;; assumes no '$@' or other rule-processing-phase-only vars
      (if (findstring "$" (subst "$$" "" rule))
         (subst "$" "$$" (native-call "or" rule)))


### Possible Arg Syntax

    $(_args)                -->  {:*}
    $(_arg1)                -->  {:1}
    $(call _nameArgs,NAME)  -->  {NAME:*}
    $(call _nameArg1,NAME)  -->  {NAME:1}

## Advice

Some tips on organizing a build system.

### O(N) Multi-level Make

Use O(N) multi-level make for large projects, but *not* recursive make in
the general sense.  Recursive make is not bad because of the cost of
invoking make N times.  Recursive make is bad because "diamonds" in the
dependency graph can result in an *exponential* number of invocations of
make.  We can eliminate this by creating a top-level "orchestrating" make
that directly invokes each sub-make at most once.  It knows of the
dependencies between the sub-makes so it can invoke them in the proper
order.

Ideally, there are just two levels -- one top-level "orchestration" make,
and some number of second-level "component" sub-makes -- but this can be
extended to more layers without losing O(N) performance as long as we ensure
that each makefile is invoked only by one other makefile.

In Minion, we can define the the follwing class:

    # Submake(DIR,[goal:GOAL]) : Run `make [GOAL]` in DIR
    Submake.inherit = Phony
    Submake.command = make -C $(_arg1) $(patsubst %,'%',$(call _namedArgs,goal))

The default target of the top-level make will be a sub-make that builds the
final results of the project:

    Alias(default).in = Submake(product)

Dependencies between sub-makes must be expressed in the top level makefile
like this:

    Submake(product).in = Submake(lib1) Submake(lib2)
    Submake(lib1).in = Submake(idls)
    ...

In the lower-level directories, typing `make` will build the default goal
for the current component without updating external dependencies.  We can
add the following line to a component makefile so that `make outer` will
build all its dependencies and then build its default goal:

    Alias(outer).in = Submake(../Makefile,goal:Submake(DIR1))

...or...

    Alias(outer).command = make -C ../Makefile 'Submake(DIR1)'


### Flat projects

Strive for the flattest possible project structure.  Fight the tendency that
most projects have, which is to drift toward an ever-more elaborate
hierarchy with many nested directories.  Structures like this present
unnecessary complexity.  The need to navigate the structure presents an
initial learning curve for developer and, later, an ongoing burden.

Some common reasons for these elaborate trees include:

 1. A desire to reflect the hierarchical structure of the software build.

 2. A desire to reflect the organizational structure.

One problem with #1 is that a directory hierarchy is inadequate to capture
the structure of software, because software structure is more generally an
directed graph and not a tree.  (Instead, with a flat structure, we can
express the relationships between components, including inter-dependencies,
in the top-level makefile.)

The bigger problem with #1, and it shares this with #2, is it takes a
volatile aspect of the software and casts it in stone.  Regarding #1,
services may be grouped in different processes at different stages of
development, components may move from one library to another, and so on.
Regarding #2, software projects almost always outlive the divisions of
responsibilities.  People move on, groups are reorganized, and so on, but
the cost to the organiation of moving all the files around in the
development tree can be enormous.

The practical reality is that restructuring the *code* -- moving or renaming
files and directory en masse -- is a very expensive operation, disrupting
many day-to-day activities of those who work on the code.  So the tree ends
up reflecting some past structure of the software or organization, with
directories named after teams or software components that no longer exist.
Over time, it becomes a bewildering mish-mash of recent and old structures.
The more elaborate the tree structure, the more likely it is to be wrong.

At that point, it should be clear that a flat project structure is actually
the easiest one for managing access control and tracking responsibilities,
because at least you can easily enumerate the sub-projects, versus having
them scattered about various levels of a hierarchical tree.
