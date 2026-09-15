(require "core")
(require "base.scm")


;;----------------------------------------------------------------
;; _info, _qv, _qvn
;;----------------------------------------------------------------


(define *traceLevel* &native "")

(define (_ti)
  &native
  (subst "." "  " *traceLevel*))

(define (_ti+)
  &native
  (native-eval (.. "*traceLevel* := ." *traceLevel*)))

(define (_ti-)
  &native
  (native-eval (.. "*traceLevel* := " (patsubst "%." "%" *traceLevel*))))


;; Quote value, with tracing-aware indentation.
;;
(define (_tqv value)
  &native
  (_qvn value "'" (_ti)))


;;----------------------------------------------------------------
;; _trace
;;----------------------------------------------------------------


;; Log entry to traced function
;;
(define (_traceIn ?a ?b ?c ?d ?e ?f ?g ?h)
  &native
  (define `1..9 "1 2 3 4 5 6 7 8 9")
  (define `(qa index value)
    (if (findstring "\n" value)
        (.. "$" index)
        (.. "'" value "'")))

  ;; bind narg without calling a function
  (foreach (nargs (or (lastword (foreach (n 1..9) (if (native-value n) n))) 0))
    (define `args (wordlist 1 nargs 1..9))
    (define `argGap (if (filter 0 nargs) "" " "))
    (define `argText (foreach (a args)
                       (qa a (native-value a))))

    (_info (.. (_ti) "(" (native-var 0) argGap argText ") ->"))
    (_ti+)
    (foreach (a args)
      (if (findstring "\n" (native-value a))
          (_info (.. (_ti) "$" a ":" (_tqv (native-value a))))))
    nil))

;; Log return from traced function FN returning VALUE
;;
(define (_traceOut fn value)
  &native
  (_ti-)
  (_info (.. (_ti) "(" fn ") <- " (_tqv value)))
  value)


(define `(traced-name var)
  (.. "TRACE*" var))


;; Instrument functions named in VARS with tracing, unless they have already
;; been instrumented.
;;
(define (_trace vars)
  &native
  (foreach (v vars)
    (define `tv
      (traced-name v))
    (define `status
      (cond ((undefined? v) (.. "function " v " not defined!"))
            ((defined? tv) (.. "already traced " v))
            ((filter v "_traceIn _traceOut _tqv _qv _qvn _ti+ _ti- _ti")
             (.. "CANNOT trace " v)) ;; circular; unending recursion
            (else
             (_fset tv (native-value v))
             (_fset v (.. "$(_traceIn)$(call _traceOut,$0,$(call " tv
                          ",$1,$2,$3,$4,$5,$6,$7,$8,$9))"))
             (.. "tracing " v " ..."))))

    (_info (.. "_trace: " status))))


;; Call-site tracing: trace call to FN with args A, B, C, ...
;;
(define (_? fn ?a ?b ?c ?d ?e ?f ?g)
  &native
  (.. (native-var "_traceIn")
      (_traceOut (.. "_? '" fn "'") (native-call fn a b c d e f g))))


;;----------------------------------------------------------------
;; Tracing tests
;;----------------------------------------------------------------

(withInfoHook
 (begin
   (expect "" (_traceIn 1 2 3))
   (expect *info* "(_traceIn '1' '2' '3') ->\n")
   (_ti-)))

(withInfoHook
 (begin
   (expect "" (_traceIn 1 "a\nb" 3))
   (expect *info*
           (.. "(_traceIn '1' $2 '3') ->\n"
               "  $2:\n"
               "    | a\n"
               "    | b\n"))
   (_ti-)))

(withInfoHook
 (begin
   (expect "3 2 1" (_traceOut "f" "3 2 1"))
   (expect *info* "(f) <- '3 2 1'\n")))


(define (traceTest a ?b ?c)
  &native
  (if (.. b c)
      (traceTest b c))
  a)

(expect 1 (traceTest 1))

(withInfoHook
 (begin
   (_trace "traceTest")
   (_trace "traceTest")
   (_trace "_ti+")
   (expect *info*
           (.. "_trace: tracing traceTest ...\n"
               "_trace: already traced traceTest\n"
               "_trace: CANNOT trace _ti+\n"
               ))))


(withInfoHook
 (begin
   (expect "$(_traceIn)$(call" (word 1 traceTest))
   (expect "$(if" (word 1 (native-value (traced-name "traceTest"))))
   (expect 1 (traceTest 1))
   (expect *info*
           (.. "(traceTest '1') ->\n"
               "(traceTest) <- '1'\n"))))


(withInfoHook
 (begin
   (expect "1" (traceTest 1 2 3))
   (expect *info*
           (.. "(traceTest '1' '2' '3') ->\n"
               "  (traceTest '2' '3') ->\n"
               "    (traceTest '3') ->\n"
               "    (traceTest) <- '3'\n"
               "  (traceTest) <- '2'\n"
               "(traceTest) <- '1'\n"))))

(withInfoHook
 (begin
   (expect 0 (traceTest 0 "multi\nline\nvalue"))
   (expect *info*
           (.. "(traceTest '0' $2) ->\n"
               "  $2:\n"
               "    | multi\n"
               "    | line\n"
               "    | value\n"
               "  (traceTest $1) ->\n"
               "    $1:\n"
               "      | multi\n"
               "      | line\n"
               "      | value\n"
               "  (traceTest) <- \n"
               "    | multi\n"
               "    | line\n"
               "    | value\n"
               "(traceTest) <- '0'\n"))))

(withInfoHook
 (begin
   (expect "9" (_? "_hashGet" ":a b:9" "b"))
   (expect *info*
           (.. "(_? '_hashGet' ':a b:9' 'b') ->\n"
               "(_? '_hashGet') <- '9'\n"))))
