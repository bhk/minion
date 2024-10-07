# After including start-minion.mk, the including Makefile must invoke $(end)
# in order to invoke Minion's rule processing.  Between start-minion.mk and
# $(end), the Makefile may make use of exported functions, and may override
# variables (e.g. class properties) defined by Minion.

minionStart = 1
include $(dir $(lastword $(MAKEFILE_LIST)))minion.mk
