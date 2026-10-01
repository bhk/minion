;; base-q.scm

(require "core")
(require "base.scm" &private)

;; test _qv, _qvn

(expect "a b" (_qvn "a b"))
(expect "\n  | a\n  | b" (_qvn "a\nb"))
(expect "'a b'" (_qv "a b"))

;; _set

(define `(test key value)
  (_set key value)
  (expect (native-value key) value))
(test "test_x \ty(" 1)
(test "test_set" "a\\b#c\\#\\\\$v\nz")
(test "test$:a=b(" "a\\b#c\\#\\\\$v\nz")

;; _fset

(define `(test name value-in ?value-out-if-different)
(define `value-out (or value-out-if-different value-in))
(_fset name value-in)
(expect value-out (native-call name)))

;; (test "test_f:x=y" "x")   ;; expected to fail
  ;; (test "test_f(a)" "abc")  ;; expected to fail
(test "test_f x=y" "fxy")

(test "test_f" "x")
(expect (native-value "test_f") "x")  ;; no prefix
(test "test_f" "")
(expect (native-value "test_f") "")   ;; no prefix
(test "test_f" "$(or 1)" "1")
(test "test_f" "   abc  \n\ndef\n")
(test "test_f" "echo '#-> x'")
(test "test_f" "a\\b\\\\c\\#\\")

;; _argHash

(expect (_argHash "a:b:c,d:e,f,g") "a:b:c d:e :f :g")
(expect (_argHash "a") ":a")
(expect (_argHash "a,b,c") ":a :b :c")
(expect (_argHash "C(a)") ":C(a)")
(expect (_argHash "C(a:b)") ":C(a:b)")
(expect (_argHash "x:C(a)") "x:C(a)")
(expect (_argHash "c(a,b:1!R()),d,x:y") ":c(a,b:1!R()) :d x:y")
(expect (_argHash "c(a,b:1()),d,x:y")   ":c(a,b:1()) :d x:y")

(let-global ((_argError (lambda (arg) (subst "`(" "<(>" "`)" "<)>" arg))))
  (expect (_argHash "c(a,b:1()),d,x:y)(") ":c(a,b:1()) :d x:y<)><(>"))

(expect (_argHash ",") ": :")
(expect (_argHash ",a,b,") ": :a :b :")

;; _hashGet

(expect (_hashGet ":a :b x:y" "") "a b")
(expect (_hashGet ":a :b x:y" "x") "y")

;; _describeVar

(set-native "sv-s" "a\nb$")
(set-native-fn "sv-r1" "a b")
(set-native-fn "sv-r2" "a\nb")

(expect (_describeVar "sv-s" "P: ")  "P: sv-s := a$(\\n)b$$")
(expect (_describeVar "sv-r1" "P: ")  "P: sv-r1 = a b")
(expect (_describeVar "sv-r2" "P: ")  (.. "P: define sv-r2\n"
                                          "P: a\n"
                                          "P: b\n"
                                          "P: endef"))
