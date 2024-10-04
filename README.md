# Minion

Minion is a Make-based build tool designed to enable build descriptions that
are:

* Lightweight

  Minion does not pollute your project with external dependencies.  Projects
  need to include just one file, minion.mk, and it depends only on GNU Make
  3.81 or higher.

* Maintainable

  Builds are described in a declarative style.  Classes and inheritance
  provide for elegant, concise, DRY descriptions.  Makefiles generally
  need not concern themselves with output file locations.

* Fast

  Minion supports cached (pre-compiled) makefiles.  There is usually no need
  for `make clean` after changes to Makefiles; only the affected targets
  need to be rebuilt.  Minion significantly speeds up Make's rule processing
  by disabling its implicit rules, which are unneeded, given Minion's
  functionality.

[Walk-Through](demo.md)

[Reference](minion.md)
