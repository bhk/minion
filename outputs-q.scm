(require "core")
(require "base.scm")
(require "outputs.scm" &private)

;; nest-path

(expect (nest-path "out/" "Class/./a/../b/c/")
        "out/Class/a/_../b/c/")

(expect (nest-path "out/" "C/./out/D/e/f/")
        "out/C_D/e/f/")
