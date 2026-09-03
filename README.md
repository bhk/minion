# Minion

Minion is a Make-based build tool (or library, or DSL, as you will). It lets
you write makefiles this look like this:

    default = Test(CExe(foo_test.c)) Run(CExe(main.c,foo.c))
    include minion.mk

How is Minion different from other build tools?

* Maintainable project files: Builds are described in a declarative style.
  Each build step takes the form of an expression.  Dependency relationships
  inherent in the build description are automatically handled by Minion, so
  you don't need to repeat yourself.  Classes and inheritance provide for
  elegant and concise customization.

* Lightweight dependencies: Minion does not pollute your project.  There is
  no "installation" step, other than copying a single file, `minion.mk` into
  your project.  The only external dependencies are ubiquitous: GNU Make
  3.81+ and BASH or a compatible shell.

* Speed: Incremental nothing-to-do builds take milliseconds, not minutes,
  even on large projects.  Comprehensive dependency checking means that
  `make clean` is almost never needed.  Minion can greatly outperform
  "vanilla" Make files by disabling Make's implicit rules and obviating
  Make's pattern rule processing and many other elaborate features that
  are redundant with Minion's more powerful constructs.

If you are intrigued, this [walk-through](demo.md) provides a gentle introduction.

If you are more seriously interested, the [Reference](minion.md) provides a
more comprehensive, contract-oriented discussion.
