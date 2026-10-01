(require "core")
(require "base.scm")
(require "rules.scm" &private)

;; _expand

(set-native-fn "ev0" "")
(set-native-fn "ev1" "a1 b1")
(set-native-fn "ev2" "a2 @ev1 c@ev1 c(@v) D@C@ev1 E@ev0")
(expect (_expand "E@ev0") "")
(expect (_expand "a @ev2")
        "a a2 a1 b1 c(a1) c(b1) c(@v) D(C(a1)) D(C(b1))")

(expectInError (_expand "a@undef" "x") "undefined variable 'undef'")

(let-global ((_self "C(A)"))
  (expectInError (_expand "a@" "x")
                 (.. "Invalid target: 'a@'\n"
                     "Name ends in '@'\n"
                     "Found while expanding C(A).x")))

;; _rollupOne, _rollup, _rollupEx

(set-native "R(a).needs" "R(b) R(c) x y z")
(set-native "R(b).needs" "R(c) R(d) x y z")
(set-native "R(c).needs" "R(d)")
(set-native "R(d).needs" "R(e)")
(set-native "R(e).needs" "")

(expect (_rollupOne "R(a)")
        "R(b) R(c) R(d) R(e)")

(expect (_rollup "R(a)")
        "R(a) R(b) R(c) R(d) R(e)")

(expect (strip (_rollupEx "R(a)" ""))
        "R(a) R(b) R(c) R(d) R(e)")

(expect (strip (_rollupEx "R(a)" "R(d)"))
        "R(a) R(b) R(c)")

(set-native (rulecache-needs-var "R(d)") "R(x)")
(set-native "R(x).needs" "")

(expect (strip (_rollupEx "R(a)" "R(d)"))
        "R(a) R(b) R(c) R(x)")

;; _group

(expect (_group "a | c d e f g h" 3)
        "a|0|1|0c d|0e|0f g|0h|0")

(define `(group-test list n out)
  (expect (foreach (g (_group list n))
            (.. "<" (foreach (i (_ungroup g)) i) ">"))
          out))

(group-test "a b c"    1 "<a> <b> <c>")
(group-test ""         2 "")
(group-test "a"        2 "<a>")
(group-test "a b"      2 "<a b>")
(group-test "a b c"    2 "<a b> <c>")
(group-test "a b c d e f g h"  3 "<a b c> <d e f> <g h>")
