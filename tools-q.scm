(require "core")
(require "base.scm")
(require "tools.scm" &private)

;; _wildcard

(expect "base-q.scm" (_wildcard "ba*-q.scm"))
(expect "base.scm" (_wildcard "b*e.scm"))
(expect (sort "ba*-q.scm b*e.scm") globLog)

;; _shell

(expect "base-q.scm" (_shell "echo ba*-q.scm"))
(expect "base.scm" (_shell "echo b*e.scm"))
(expect "echo ba*-q.scm" (promote (word 2 shellLog)))

;; _var

(define VFOO &native 1)
(define VBAR &native 2)
(expect "1" (_var "VFOO"))
(expect "2" (_var "VBAR"))
(expect "VBAR VFOO" varLog)

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

;; _inferIDs

(set-native "IC(a.c).out" "out/a.o")
(set-native "IP(a.o).out" "out/P/a")
(set-native "IP(IC(a.c)).out" "out/IP_IC/a")


(expect (_inferIDs "a.x a.o IC(a.c)" "IP.o")
        "a.x IP(a.o) IP(IC(a.c))")

(expect (_inferIDs "y a.x a.o IC(a.c)" "IP.o")
        "y a.x IP(a.o) IP(IC(a.c))")

;; _relpath


(expect (_relpath "a/b/c" "/x") "/x")
(expect (_relpath "a" "x/y") "x/y")
(expect (_relpath "a/b" "x/y") "../x/y")
(expect (_relpath "x/b" "x/y") "y")
(expect (_relpath "a/b/c"
                  "a/x/y") "../x/y")

;; trim-empties

(define `(tte in out)
  (expect (subst "!" D out) (trim-empties (subst "!" D in))))

(tte "!a! ! ! !b! ! !c! ! !"
     "!a! ! ! !b! ! !c!")
(tte "!a! ! ! !b! ! !c!"
     "!a! ! ! !b! ! !c!")
(tte "! ! !" nil)

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

;; _buildGoalID

(define alias1 &native "x")

(expect "Alias(alias1)" (_buildGoalID "alias1"))
(expect "_BuildGoal(@alias1)" (_buildGoalID "@alias1"))
(expect "_BuildGoal(a(b))" (_buildGoalID "a(b)"))
(native-eval "TestClass(arg).prop = 1") ;; not to be confused with an alias
(expect "_HelpGoal(TestClass(arg).prop)" (_buildGoalID "TestClass(arg).prop"))
