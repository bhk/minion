include minion.mk

V := $(\s)$(\t)\a\\b$(\n)"c))(d\#e
W := a\$(\H)\\$(\H)\\\$(\H)

$(info V = $V)
$(info W = $W)

\q = "

# Parenthesis encoding:
#  1) $
#  2) Leading space
#  3) parens
#  4) #
#  5) \n
#  
ifneq ($V,  $(\s)	\a\\b$(\n)"c$]$]$[d\#e)
  $(error FAIL)
endif

ifneq ($W,a\\\#\\\\\#\\\\\\\#)
  $(error FAIL)
endif

# Double-quote encoding:
#  1) $
#  2) "
#  3) #
#  4) \n
#
ifneq "$V" " 	\a\\b$(\n)$(\q)c))(d\#e"
  $(error FAIL)
endif


default: ; @
