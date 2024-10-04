

define lazyRecipe
# comment
echo foo
@echo bar
echo baz
endef

test:
	$(lazyRecipe)

test2: ; $(lazyRecipe)
