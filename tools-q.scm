(require "core")
(require "base.scm")
(require "tools.scm" &private)

;; _escape

(expect "a$]$$x$;$;" (_escape "a)$x,,"))
(expect "a)$x,," (native-call "or" (.. "$(if a," (_escape "a)$x,,") ",)")))

;; _vvEnc

(define (checkVV data substr)
  (define viaVar &native (_vvEnc data substr))
  (define vvIsOK &native nil)
  (define `ifeq (.. "ifeq \"$(viaVar)\" \"" viaVar "\"\n"
                    "  vvIsOK = 1\n"
                    "endif\n"))
  (_eval ifeq)
  (expect 1 vvIsOK))

;; Leading and trailing spaces
(checkVV "  abc  " "c")
;; Trailing "\" can cause problems if not guarded
(checkVV "abc\\" "x")
;; Special characters
(checkVV "# \\# \\ \\\\ $a $$a $(\t)$(\n)" "-")


;; _recipe, _lazy

(expect "\ta$$b\n\tc\n" (_recipe "a$b\n\nc"))
(expect "\ta$b\n" (_recipe (_lazy "a$b")))

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

;; _inferIDs

(set-native "IC(a.c).out" "out/a.o")
(set-native "IP(a.o).out" "out/P/a")
(set-native "IP(IC(a.c)).out" "out/IP_IC/a")


(expect (_inferIDs "a.x a.o IC(a.c)" "IP.o")
        "a.x IP(a.o) IP(IC(a.c))")

(expect (_inferIDs "y a.x a.o IC(a.c)" "IP.o")
        "y a.x IP(a.o) IP(IC(a.c))")

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


;; _relpath


(expect (_relpath "a/b/c" "/x") "/x")
(expect (_relpath "a" "x/y") "x/y")
(expect (_relpath "a/b" "x/y") "../x/y")
(expect (_relpath "x/b" "x/y") "y")
(expect (_relpath "a/b/c"
                  "a/x/y") "../x/y")

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


;; _graph

  (define `test-graph
    { 0: [1 2 4],
      1: [3],
      2: [3],
      A: "D C B",
      B: "C E",
      C: "D",
      })

  (define (test-children G node)
    (dict-get node G))

  (define (test-name cxt node)
    (if (filter 3 node)
        (.. "<" node ">")
        node))

  (expect
   (concat-vec [""
                "0"
                "|  "
                "+-> 1"
                "|   |  "
                "+-> |   2"
                "|   |   |  "
                "|   +-> +-> <3>"
                "|  "
                "+-> 4"
                ""]
               "\n")
   (_graph (native-name test-children) (native-name test-name) test-graph
           "0 1 2 3 4"))

;; _traverse

(expect "A B C D E"
        (_traverse (native-name test-children) test-graph "A"))

;; _unique

(expect (_unique "a b a c a b c c") "a b c")
(expect (_unique "a b % ^ a b % ^") "a b % ^")
