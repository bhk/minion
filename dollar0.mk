
var = $(info var:$0,$1,$2,$3)
func = $(info func:$0,$1,$2,$3)$(var)

$(call func,1,2,3)

$(eval func = $(value func))

$(call func,4,5,6)


rp: ; echo $(call func,7,8,9)

