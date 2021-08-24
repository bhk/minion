;; prototype.scm:  SCAM prototypes of functions for Minion

(require "core")
(require "string")

;;----------------------------------------------------------------
;; Utilities
;;----------------------------------------------------------------

(define *var-functions* nil)

;; Mark a function as safe to be replaced with a variable reference
;;  $(call FN,$1)    -> $(FN)
;;  $(call FN,$1,$2) -> $(FN)
;; Must be non-recursive, and must not have optional arguments.
;;
(define (VF! fn-name)
  (set *var-functions*
       (append *var-functions* fn-name)))


(define single-chars
  (.. "a b c d e f g h i j k l m n o p q r s t u v w x y z "
      "A B C D E F G H I J K L M N O P Q R S T U V W X Y Z "
      ";"))

;; Rename variable references and "foreach" bindings
;;
(define (rename-vars fn-body froms tos)
  (define `(var-ref name)
    (if (filter single-chars name)
        (.. "$" name)
        (.. "$(" name ")")))

  (define `from (word 1 froms))
  (define `to (word 1 tos))
  (define `renamed
    (subst (.. "foreach " from ",") (.. "foreach " to ",")
           (var-ref from) (var-ref to)
           fn-body))

  (if froms
      (rename-vars renamed (rest froms) (rest tos))
      fn-body))


(expect (rename-vars "$(foreach a,bcd,$(foreach bcd,a $a,$(bcd)))"
                     "a bcd" "A BCD")
        "$(foreach A,bcd,$(foreach BCD,a $A,$(BCD)))")


;; Collapse function calls into variable references.
;;
(define (omit-calls body)
  (foldl (lambda (text fname)
           (subst (.. "$(call " fname ")")
                  (.. "$(" fname ")")
                  (.. "$(call " fname ",$1)")
                  (.. "$(" fname ")")
                  (.. "$(call " fname ",$1,$2)")
                  (.. "$(" fname ")")
                  (.. "$(call " fname ",$1,$2,$3)")
                  (.. "$(" fname ")")
                  (.. "$(call " fname ",$1,$2,$3,$4)")
                  (.. "$(" fname ")")
                  text))
         body
         *var-functions*))


(define *exports* nil)


;; Mark FN-NAME as a function to be exported to Minion, and perform
;; relevant translations.
;;
(define (export fn-name is-vf ?vars-to-in ?vars-from-in)
  ;; Avoid ";" because Minion uses `$;` for ","
  (define `vars-to (or vars-to-in "w x"))
  (define `vars-from (or vars-from-in "; ;; ;;; ;;;; ;;;;;"))

  (if is-vf
      (VF! fn-name))
  (set-native-fn fn-name
       (omit-calls
        (rename-vars (native-value fn-name) vars-from vars-to)))
  (set *exports* (conj *exports* fn-name)))


(define (export-comment text)
  (set *exports* (conj *exports* (.. "#" text))))

;; Output a SCAM function as Make code, renaming automatic vars.
;;
(define (show-export fn-name)
  (define `minionized
    (subst "$  " "$(\\s)"     ;; SCAM runtime -> Minion make
           "$ \t" "$(\\t)"    ;; SCAM runtime -> Minion make
           "$ " ""            ;; not needed to avoid keywords in "=" defns
           "$(if ,,,)" "$;"   ;; SCAM runtime -> Minion make
           "$(if ,,:,)" ":$;" ;; SCAM runtime -> Minion make
           "$(&)" "$&"        ;; smaller, isn't it?
           "$`" "$$"          ;; SCAM runtime -> Minion make
           (native-value fn-name)))

  (define `escaped
    (subst "\n" "$(\\n)" "#" "\\#" minionized))

  (print fn-name " = " escaped))


(define (show-exports)
  (for (e *exports*)
    (if (filter "#%" e)
        (print "\n" e "\n")
        (show-export e))))



;;----------------------------------------------------------------
;; Object system
;;----------------------------------------------------------------

(export-comment " object system")

(print "Imports: \\H \\n \\L \\R [ ]")
(define \H &native "#")
(define \n &native "\n")
(set-native "\\L" "{")
(set-native "\\R" "}")


;; Return non-nil if VAR has been assigned a value.
;;
(define `(bound? var)
  (filter-out "u%" (native-flavor var)))

(define `(undefined? var)
  (filter "u%" (native-flavor var)))

(define `(recursive? var)
  (filter "r%" (native-flavor var)))

(define `(simple? var)
  (filter "s%" (native-flavor var)))

;; Return VAR if VAR has been assigned a value.
;;
(define `(boundName? var)
  (if (filter "u%" (native-flavor var)) "" var))


;; Set variable named KEY to VALUE; return VALUE.
;;
;; We assume KEY does not contain ":", "=", "$", or whitespace.
(define (_set key value)
  &native
  (define `(escape str)
    "$(or )" (subst "$" "$$" "\n" "$(\\n)" "#" "$(\\H)" str))
  (.. (native-eval (.. key " := " (escape value)))
      value))

(export (native-name _set) 1)


(begin
  (define `(test value)
    (_set "tmp_set_test" value)
    (expect (native-var "tmp_set_test") value))
  (test "a\\b#c\\#\\\\$v\nz"))


;; Assign a recursive variable, given the code to be evaluated.  The
;; resulting value will differ, but the result of its evaluation should be
;; the same as that of VALUE.
;;
(define `(_setfn name value)
  &native
  (native-eval (.. name " = $(or )" (subst "\n" "$(\\n)" "#" "$(\\H)" value))))


(begin
  (define `(test var-name)
    (define `out (.. "~" var-name))
    (_setfn out (native-value var-name))
    (expect (native-var var-name) (native-var out)))

  (native-eval "define TX\n   abc   \n\n\nendef\n")
  (test "TX")
  (native-eval "TX = a\\\\\\\\c\\#c")
  (test "TX")
  (native-eval "TX = echo '#-> x'")
  (test "TX"))


;; Return value of VAR, evaluating it only the first time.
;;
(define (_once var)
  &native
  (define `cacheVar (.. "_|" var))

  (if (bound? cacheVar)
      (native-var cacheVar)
      (_set cacheVar (native-var var))))

(export (native-name _once) nil)

(begin
  ;; test _once
  (native-eval "fv = 1")
  (native-eval "ff = $(fv)")
  (expect 1 (_once "ff"))
  (native-eval "fv = 2")
  (expect 2 (native-var "ff"))
  (expect 1 (_once "ff")))


;; Dynamic state during property evaluation enables `.`, `C`, `A`, and
;; `super`:
;;    C = C
;;    A = A
;;
(declare C &native)
(declare A &native)



;; This "mock" _error records the last error for testing
;;
(define *last-error* nil)
(define (_error msg)
  &native
  (set *last-error* msg))



;; Construct an E1 (undefined property) error message
;;
(define `(e1-msg who outVar class arg)
  (define `prop
    (word 2 (subst "." ". " outVar)))

  (define `who-desc
    (cond
     ;; {inherit}
     ((filter "^&%" who) " from {inherit} in")
     ;; {prop}
     ((filter "^%" who) (.. " from {" prop "} in"))
     ;; $(call .,P,$0)
     (else "during evaluation of")))

  (define `cause
    (cond
     ((undefined? (.. class ".inherit"))
      (.. ";\n" class "is not a valid class name "
          "(" class ".inherit is not defined)"))
     (who
      (foreach (src-var (patsubst "&%" "%" (patsubst "^%" "%" who)))
        (.. who-desc ":\n" src-var " = " (native-value src-var))))))

  (.. "Reference to undefined property '" prop "' for "
      class "[" arg "]" cause "\n"))


;; Report error: undefined property
;;    Property 'P' is not defined for C[A]
;;    + C[A] was used as a target, but 'C.inherit' is not defined.
;;    + Property 'P' is not defined for C[A]; Used by {P} in DEFVAR.
;;    + '{inherit}' from DEFVAR failed for C[A].  Ancestor classes = ....
;;
(define (_getE1 outVar _ _ who)
  &native
  (_error (e1-msg who outVar C A)))

(export (native-name _getE1) 1)


;; Get the inheritance chain for a class (the class and its inherited
;; classes, transitively).
;;
(define (_chain c)
  &native
  (._. c
       (foreach (sup (native-var (.. c ".inherit")))
         (_chain sup))))

(export (native-name _chain) nil)


(define `(scopes class)
  (define `cache-var (.. "&|" class))

  (or (native-var cache-var)
      (_set cache-var (_chain class))))


;; Return all inherited definitions of P for CLASS
;;
(define (_& p)
  &native
  (strip
   (foreach (c (scopes C))
     (if (undefined? (.. c "." p))
         nil
         (.. c "." p)))))

(export (native-name _&) 1)


;; User-defined C[A].PROP var
(define `(cap-var prop) (.. C "[" A "]." prop))

;; Compiled property PROP for class C
(define `(cp-var prop)  (.. "&" C "." prop))

(declare (_cp outVar chain nextOutVar who) &native)

(define `(_cp-cache outVar chain nextOutVar who)
  (if (native-value outVar)
      outVar
      (_cp outVar chain nextOutVar who)))

;; Compile first definition in CHAIN, writing result to OUTVAR, returning
;; OUTVAR.  NEXTOUTVAR = outVar for next definition in chain (used only when
;; the first definition contains {inherit}.
;;
;; A)  &C[A].P  "C[A].P B.P A.P"  &C.P
;;     &C.P     "B.P A.P"         _&C.P
;;     _&C.P    "A.P"             __&C.P
;;
;; B)  &C.P     "B.P A.P"        _&C.P
;;     _&C.P    "A.P"            __&C.P
;;
(define (_cp outVar defVars nextOutVar who)
  &native

  (define `success
    (foreach (srcVar (word 1 defVars))
      (define `src
        (native-value srcVar))

      (define `inherit-var
        (_cp-cache nextOutVar
                   (rest defVars)
                   (.. "_" nextOutVar)
                   (.. "^" outVar)))

      (define `out
        (if (recursive? srcVar)
            (subst "{" "$(call .,"
                   "}" (.. ",^" srcVar ")")
                   (if (findstring "{inherit}" src)
                       (subst "{inherit}" (.. "$(call " inherit-var ")")
                              src)
                       src))
            (subst "$" "$$" src)))

      (.. (_setfn outVar out)
          ;;(print outVar " = " (native-value outVar))
          outVar)))

  (or success
      (_getE1 outVar defVars nextOutVar who)
      outVar))

(export (native-name _cp) nil)


;; Evaluate property P for instance C[A]  (don't cache result)
;;
(define (_! p who)
  &native
  (native-call
   (if (undefined? (cap-var p))
       (_cp-cache (cp-var p) (_& p) (.. "_" (cp-var p)) who)
       ;; don't bother checking
       (_cp (.. "&" (cap-var p))
           (._. (cap-var p) (_& p))
           (cp-var p)
           who))))

(export (native-name _!) nil)


;; Evaluate property P for current instance (given by dynamic C and A)
;; and cache the result.
;;
;;  WHO = requesting target ID
;;
;; Performance notes:
;;  * . results are cached (same C, A, P => fast access)
;;  * &C.P is cached (same C => just a variable reference)
;;
(define (. p ?who)
  &native
  (define `cache-var
    (.. "~" C "[" A "]." p))

  (if (simple? cache-var)
      (native-var cache-var)
      (_set cache-var (_! p who))))

(export (native-name .) nil)


;; Extract class name from ID stored in variable `A`.  Return (_getE) if
;; class does not contain "[" or begins with "[".
;;
(define `(extractClass)
  (subst "[" "" (filter "%[" (word 1 (subst "[" "[ " A)))))

;; Extract argument from ID stored in variable `A`, given class name `C`.
;; Call _getE0 and return nil if argument is empty.
;;
(define `(extractArg)
  (subst (.. "&" C "[") nil (.. "&" (patsubst "%]" "%" A))))


;; Report error: mal-formed instance name
;;
(define (_getE0)
  &native
  ;; When called from `get`, A holds the instance name
  (define `id A)

  (define `reason
    (if (extractClass)
        "empty ARG"
        (if (filter "[%" id)
            "empty CLASS"
            "missing '['")))

  (_error (.. "Mal-formed instance name '" id "'; " reason " in CLASS[ARG]")))

(export (native-name _getE0) 1)


(define (get p ids)
  &native
  (foreach (A ids)
    (if (filter "%]" A)
        ;; instance
        (foreach (C (or (extractClass) (_getE0)))
          (foreach (A (or (extractArg) (_getE0)))
            (. p)))
        ;; file
        (foreach (C "File")
          (or (native-var (.. "File." p))
              ;; error case...
              (. p))))))

;; Override automatic variable names so they will be visible to otheeginr
;; functions as $C and $A.
(export (native-name get) nil "A C A")


(begin
  (set-native-fn "A.inherit" "")
  (set-native-fn "B1.inherit" "A")
  (set-native-fn "B2.inherit" "A")
  (set-native-fn "C.inherit" "B1 B2")

  (expect 1 (see "not a valid class" (e1-msg nil nil "CX" "a")))
  (expect 1 (see "from {x} in:\nC.foo =" (e1-msg "^C.foo" "_&C.x" "C" "a")))
  (expect 1 (see "from {inherit} in:\nB.x =" (e1-msg "^&B.x" "_&C.x" "C" "a")))
  (expect 1 (see "during evaluation of:\nB.x =" (e1-msg "&B.x" "_&C.x" "C" "a")))

  (expect (strip (scopes "C")) "C B1 A B2 A")
  (expect (strip (scopes "C")) "C B1 A B2 A")

  (set-native-fn "A.x" "(A.x:$C)")
  (set-native-fn "A.y" "(A.y)")
  (set-native    "A.i" " (A.i) ")

  (set-native-fn "B1.y" "(B1.y)")
  (set-native-fn "B2.y" "(B2.y)")

  (set-native-fn "C.z" "(C.z)")
  (set-native-fn "C.i" "<C.i:{inherit}>")        ;; recursive w/ {inherit}

  (set-native    "C[a].s" "(C[a].s:$C[$A]{x})")  ;; simple
  (set-native-fn "C[a].r" "(C[a].r:$C[$A])")     ;; recursive
  (set-native-fn "C[a].p" "(C[a].p:{x})")        ;; recursive w/ prop
  (set-native-fn "C[a].i" "<C[a].i:{inherit}>")  ;; recursive w/ {inherit}

  (let-global ((C "C")
               (A "a"))
    ;; chain
    (expect (_& "z") "C.z")
    (expect (_& "x") "A.x A.x")
    (expect (_& "y") "B1.y A.y B2.y A.y")

    ;; compile-src & _cc
    ;;(expect (compile-src "C[a].s" "-" "") "(C[a].s:$$C[$$A]{x})")
    ;;(expect (compile-src "C[a].p" "-" "") "(C[a].p:${call .,x})")

    ;;(expect (compile-src "C[a].i" "xCP" "C.i A.i") "<C[a].i:$(xCP)>")
    ;;(expect (native-value "xCP") "$(or )<C.i:$(_xCP)>")
    ;;(expect (native-value "_xCP") "$(or ) (A.i) ")

    ;; _cp
    (expect (_cp "cpo1" "C[a].s" "_cpo1" nil) "cpo1")
    (expect (native-value "cpo1") "$(or )(C[a].s:$$C[$$A]{x})")
    (expect (_cp "cpo2" "C[a].p" "_cpo2" nil) "cpo2")
    (expect (native-value "cpo2") "$(or )(C[a].p:$(call .,x,^C[a].p))")
    (expect (_cp "cpo3" "C[a].i C.i A.i" "_cpo3" nil) "cpo3")
    (expect (native-value "cpo3") "$(or )<C[a].i:$(call _cpo3)>")
    (expect (native-value "_cpo3") "$(or )<C.i:$(call __cpo3)>")
    (expect (native-value "__cpo3") "$(or ) (A.i) ")

    ;; _!

    (expect (_! "s" nil) "(C[a].s:$C[$A]{x})")      ;; non-recursive CAP
    (expect (_! "r" nil) "(C[a].r:C[a])")           ;; recursive CAP

    (expect (_! "x" nil) "(A.x:C)")                 ;; undefined CAP
    (expect (native-value "&C.x") "$(or )(A.x:$C)")
    (expect (_! "x" nil) "(A.x:C)")

    (expect (_! "p" nil) "(C[a].p:(A.x:C))")        ;; recursive CAP w/ prop
    (expect (_! "i" nil) "<C[a].i:<C.i: (A.i) >>")  ;; recursive CAP w/ inherit

    ;; .

    (expect (. "x") "(A.x:C)")
    (expect (. "x") "(A.x:C)")  ;; again (after caching)

    nil)

  (set-native-fn "File.id" "$C[$A]")
  (expect (get "x" "C[a]") "(A.x:C)")
  (expect (get "id" "f") "File[f]")

  ;; caching of &C.P

  (expect "$(or )(A.x:$C)" (native-value "&C.x"))
  (set-native-fn "&C.x" "NEW")
  (expect (get "x" "C[b]") "NEW")
  (set-native-fn "C[i].x" "<{inherit}>")
  (expect (get "x" "C[i]") "<NEW>")

  ;; error reporting

  (define `(error-contains str)
    (expect 1 (see str *last-error*)))

  (expect (get "p" "[a]") nil)
  (error-contains "'[a]'; empty CLASS in CLASS[ARG]")

  (expect (get "p" "Ca]") nil)
  (error-contains "'Ca]'; missing '[' in CLASS[ARG]")

  (expect (get "p" "C[]") nil)
  (error-contains "'C[]'; empty ARG in CLASS[ARG]")

  (expect (get "asdf" "C[a]") nil)
  (error-contains "undefined")

  (set-native-fn "C.e1" "{inherit}")
  (expect (get "e1" "C[a]") nil)
  (error-contains "undefined")
  (error-contains "from {inherit} in:\nC.e1 = {inherit}")

  (set-native-fn "C[a].e2" "{inherit}")
  (expect (get "e2" "C[a]") nil)
  (error-contains (.. "undefined property 'e2' for C[a] from "
                      "{inherit} in:\nC[a].e2 = {inherit}"))

  (set-native-fn "C.eu" "{undef}")
  (expect (get "eu" "C[a]") nil)
  (error-contains (.. "undefined property 'undef' for C[a] "
                      "from {undef} in:\nC.eu = {undef}"))

  nil)


;;----------------------------------------------------------------
;; Misc
;;----------------------------------------------------------------

(export-comment " misc")

(define `(isInstance target)
  (filter "%]" target))


;; Mock implementation of `get`

;; (define *props* nil)  ;; "canned" answers
;;
;; (define (get prop id)
;;   &native
;;
;;   (define `key (.. id "." prop))
;;
;;   (cond
;;    ((not (isInstance id))
;;     (dict-get prop {out: id}))
;;
;;    ((not (dict-find key *props*))
;;     (expect key "NOTFOUND"))
;;
;;    (else
;;     (dict-get key *props*))))
;;

(define OUTDIR
  &native
  ".out/")


(define (_isIndirect target)
  &native
  (findstring "*" (word 1 (subst "[" "[ " target))))

;; We expect this to be provided by minion.mk
;;(export (native-name _isIndirect) 1)


(define (_ivar id)
  &native
  (lastword (subst "*" " " id)))

(export (native-name _ivar) 1)


(define `(pair id file)
  (.. id "$" file))

(define (_pairIDs pairs)
  &native
  (filter-out "$%" (subst "$" " $" pairs)))

(export (native-name _pairIDs) 1)


(define (_pairFiles pairs)
  &native
  (filter-out "%$" (subst "$" "$ " pairs)))

(export (native-name _pairFiles) 1)

(expect "a.c" (_pairIDs "a.c"))
(expect "C[a.c]" (_pairIDs "C[a.c]$a.o"))

(expect "a.c" (_pairFiles "a.c"))
(expect "a.o" (_pairFiles "C[a.c]$a.o"))



;; Infer intermediate instances given a set of input IDs and their
;; corresponding output files.
;;
;; PAIRS = list of "ID$FILE" pairs, or just "FILE"
;;
(define (_inferPairs pairs inferClasses)
  &native
  (if inferClasses
      (foreach (p pairs)
        (define `id (_pairIDs p))
        (define `file (_pairFiles p))

        (define `inferred
          (word 1
                (filter "%]"
                        (patsubst (.. "%" (or (suffix file) "."))
                                  (.. "%[" id "]")
                                  inferClasses))))

        (or (foreach (i inferred)
              (pair i (get "out" i)))
            p))
      pairs))

(export (native-name _inferPairs) nil)


(set-native "IC[a.c].out" "out/a.o")
(set-native "IP[a.o].out" "out/P/a")
(set-native "IP[IC[a.c]].out" "out/IP_IC/a")

(expect (_inferPairs "a.x a.o IC[a.c]$out/a.o" "IP.o")
        "a.x IP[a.o]$out/P/a IP[IC[a.c]]$out/IP_IC/a")


;;----------------------------------------------------------------
;; Argument string parsing
;;----------------------------------------------------------------

(export-comment " argument parsing")

(define (_argError arg)
  &native
  (subst ":[" "<[>" ":]" "<]>" arg))

(VF! (native-name _argError))


;; Protect special characters that occur between balanced brackets.
;; To "protect" them we de-nature them (remove the special prefix
;; that identifies them as syntactically significant).
;;
(define (_argGroup arg ?prev)
  &native
  ;; Split at brackets
  (define `a (subst ":[" " :[" ":]" " :]" arg))

  ;; Mark tail of "[..." with extra space
  (define `b (patsubst ":[%" ":[% " a))

  ;; Merge "[..." with immediately following "]", and mark with trailing ":"
  (define `c (subst "  :]" "]: " b))

  ;; Denature delimiters within matched "[...]"
  (define `d (foreach (w c)
               (if (filter "%:" w)
                   ;; Convert specials to ordinary chars & remove trailing ":"
                   (subst ":" "" w)
                   w)))

  (define `e (subst " " "" d))

  (if (findstring ":[" (subst "]" "[" arg))
      (if (findstring arg prev)
          (_argError arg)
          (_argGroup e arg))
      arg))

(export (native-name _argGroup) nil)


;; Construct a hash from an argument.  Check for balanced-ness in
;; brackets.  Protect "=" and "," when nested within brackets.
;;
(define (_argHash2 arg)
  &native

  ;; Mark delimiters as special by prefixing with ":"
  (define `(escape str)
    (subst "[" ":[" "]" ":]" "," ":," "=" ":=" str))

  (define `(unescape str)
    (subst ":" "" str))

  (unescape
    (foreach (w (subst ":," " " (_argGroup (escape arg))))
      (.. (if (findstring ":=" w) "" "=") w))))

(export (native-name _argHash2) 1)


;; Construct a hash from an instance argument.
;;
(define (_argHash arg)
  &native
  (if (or (findstring "[" arg) (findstring "]" arg) (findstring "=" arg))
      (_argHash2 arg)
      ;; common, fast cast
      (.. "=" (subst "," " =" arg))))

(export (native-name _argHash) 1)

(expect (_argHash "a=b=c,d=e,f,g") "a=b=c d=e =f =g")
(expect (_argHash "a") "=a")
(expect (_argHash "a,b,c") "=a =b =c")
(expect (_argHash "C[a]") "=C[a]")
(expect (_argHash "C[a=b]") "=C[a=b]")
(expect (_argHash "x=C[a]") "x=C[a]")
(expect (_argHash "c[a,b=1!R[]],d,x=y") "=c[a,b=1!R[]] =d x=y")
(expect (_argHash "c[a,b=1[]],d,x=y")   "=c[a,b=1[]] =d x=y")
(expect (_argHash "c[a,b=1[]],d,x=y][") "=c[a,b=1[]] =d x=y<]><[>")

(expect (_argHash ",") "= =")
(expect (_argHash ",a,b,") "= =a =b =")


;; Get matching values from a hash
;;
(define (_hashGet hash ?key)
  &native
  (define `pat (.. key "=%"))
  (patsubst pat "%" (filter pat hash)))

(export (native-name _hashGet) nil)


(expect (_hashGet "=a =b x=y" "") "a b")
(expect (_hashGet "=a =b x=y" "x") "y")


;;----------------------------------------------------------------
;; Output file defaults
;;----------------------------------------------------------------

(export-comment " output file defaults")

;; The chief requirement for output file names is that conflicts must be
;; avoided.  Avoiding conflicts is complicated by the inference feature, which
;; creates multiple ways of expressing the same thing.  For example,
;; `LinkC[foo.c]` vs. `LinkC[CC[foo.c]]` produce equivalent results,
;; but they are different instance names, and as such must have different
;; output file names.
;;
;; The strategy for avoiding conflicts begins with including all components
;; of the instance name in the default output path, as computed by
;; Builder.out.
;;
;; When there is a single argument value and it is also the first ID named
;; by {in}, we presume it is a valid path, and we incorporate it (or its
;; {out} property) into the output location as follows:
;;
;;     Encode ".."  and "."  path elements and leading "/" for safety and to
;;     avoid aliasing -- e.g., the instance names `C[f]` and `C[./f]` need
;;     different output files.  When {outExt} does not include `%`, we
;;     incorporate the input file extension into the output directory.
;;
;;     Instance Name          outDir                   outName
;;     --------------------   ----------------------   -------------
;;     CLASS[DIRS/NAME.EXT]   OUTDIR/CLASS.EXT/DIRS/   NAME{outExt}
;;     CC[f.c]                .out/CC.c/               f.o
;;     CC[d/f.cpp]            .out/CC.cpp/d/           f.o
;;     CC[.././f.c]           .out/CC.c/_../_./        f.o
;;     CC[/d/f.c]             .out/CC.c/_root_/d/      f.o
;;
;;     Differentiate CLASS[FILE] from CLASS[ID] (where ID.out = FILE) by
;;     appending `_` to the class directory.  For readability, collapse
;;     "CLASS.EXT_/OUTDIR/..." to "CLASS.EXT_...":
;;
;;     Instance Name          outDir                   outName
;;     ---------------------  ----------------------   -------
;;     LinkC[CC[f.c]]         .out/LinkC.o_CC.c/       f
;;     LinkC[f.c]             .out/LinkC.c/            f       [*]
;;
;;     [*] Note on handling inference: We compute .outDir based on the named
;;         FILE (f.c) , not on the inferred `.out/CC.c/f.o`.
;;         Otherwise, the result would collide with LinkC[CC[f.c]].
;;
;; When the argument is an indirection, or is otherwise not a target ID used
;; in {in}, we use it as the basis for the file name.  Any "*" or "C*"
;; prefixes are merged into the class directory:
;;
;;     Instance Name          outDir                   outName
;;     --------------------   ----------------------   -----------
;;     LinkC[*VAR]            .out/LinkC_@/            VAR{outExt}
;;     LinkC[C2*VAR]          .out/LinkC_C2@/          VAR{outExt}
;;     Write[x/y/z]           .out/Write/x/y/          z{outExt}
;;
;; When the argument is complex (with named values or comma-delimited
;; values) we apply the above logic to the *first* value in the argument,
;; after including the entirety of the argument in the class directory,
;; with these transformations:
;;
;;   1. Enode unsafe characters
;;   2. Replace the first unnamed argument with a special character
;;      sequence.  This avoids excessively long directory names and reduces
;;      the number of directories needed for a large project.
;;
;;     Instance Name           outDir                          outName
;;     ---------------------   -----------------------------   ------------
;;     CLASS[D/NAME.EXT,...]   OUTDIR/CLASS.EXT__{encArg}/D/   NAME{outExt}
;;     P[d/a.c,x.c,opt=3]      .out/P.c__@1,x.c,opt@E3/d/      a
;;
;;
;; Output file names should avoid Make and shell special characters, so that
;; we do not need to quote them.  We rely on the restrictions of instance
;; syntax.  Here are the ASCII punctuation characters legal in Minion class
;; names, arguments, ordinary (source file) target IDs, and comma-delimited
;; argument values, alongside those unsafe in Bash and Make:
;;
;; File:   @ _ - + { } / ^ . ~
;; Class:  @ _ - + { } / ^   ~ !
;; Value:  @ _ - + { } / ^ . ~ !   = * [ ]
;; Arg:    @ _ - + { } / ^ . ~ ! , = * [ ] <
;; ~Make:                    ~     = * [ ] < > ? # $ % ; \ :
;; ~Bash:                    ~ !     * [ ] < > ? # $ % ; \   | & ( ) ` ' "
;;


;; Encode all characters that may appear in class names or arguments with
;; fsenc characters.
;;
(define (_fsenc str)
  &native

  (subst "@" "@0"
         "|" "@1"
         "[" "@+"
         "]" "@-"
         "=" "@E"
         "!" "@B"
         "~" "@T"
         "/" "@D"
         "<" "@l"
         "*" "@_"  ;;  ..._/.out/... -->  ..._...
         str))

(export (native-name _fsenc) 1)


;; Encode the directory portion of path with fsenc characters
;; Result begins and ends with "/".
;;
(define `(safe-path path)
  (subst "/" "//"
         "/_" "/__"
         "/./" "/_./"
         "/../" "/_../"
         "//" "/"
         "//" "/_root_/"
         (.. "/" path)))

(expect (safe-path "a.c") "/a.c")
(expect (safe-path "d/c/b/a") "/d/c/b/a")
(expect (safe-path "./../.d/_c/.a") "/_./_../.d/__c/.a")


;; Tail of _outBasis for an argument that is not being used as a target ID
;;
(define (_outBX arg)
  &native
  ;; E.g.: "/C@_ /D@_ /dir@Dvar"
  (define `a (addprefix "/" (subst "@_" "@_ " (_fsenc arg))))
  ;; E.g.: "_C@ _D@ /dir@Dvar"
  (define `b (patsubst "/%@_" "_%@" a))
  (subst " " "" "@D" "/" b))

(expect (_outBX "*var") "_@/var")
(expect (_outBX "*d/f") "_@/d/f")
(expect (_outBX "C*var") "_C@/var")
(expect (_outBX "abc") "/abc")


;; _outBasis for simple arguments
;;
;; arg = argument (a single value)
;; file = arg==in[1] ? (in[1].out || "-") : nil
;;    file => arg==in[1]
;;
(define (_outBS class arg outExt file)
  &native
  (define `.EXT
    (if (findstring "%" outExt) "" (suffix file)))

  (define `(collapse x)
    (patsubst (.. "_/" OUTDIR "%") "_%" x))

  (.. (_fsenc class)
      .EXT
      (if file
          (collapse (.. (if (isInstance arg) "_")
                        (safe-path file)))
          (_outBX arg))))

;; arg = indirection (file must be nil because arg1 is not a target ID)
(expect (_outBS "C" "*var" nil nil) "C_@/var")
;; arg = file == in[1]
(expect (_outBS "C" "d/f.c" ".o" "d/f.c")  "C.c/d/f.c")
;; arg = ID == in[1]
(expect (_outBS "P" "C[d/f.c]" nil ".out/C/f.o")  "P.o_C/f.o")
;; arg != in[1]
(expect (_outBS "P" "C[d/f.c]" nil nil)  "P/C@+d/f.c@-")


;; _outBasis for complex arguments, or non-input argument
;;
(define `(_outBC class arg outExt file arg1)
  (_outBS (.. class
              (subst (.. "_" (or arg1 "|")) "_|" (.. "_" arg)))
          (or arg1 "out")
          outExt
          file))

;; Generate path to serve as basis for output file defaults
;;
;;  class = this instance's class
;;  arg = this instance's argument
;;  outExt = {outExt} property; if it contains "%" we assume the input file
;;           prefix will be preserved
;;  file = output of first target ID mentioned in {in}  *if* the ID == arg1
;;  arg1 = (word 1 (_getHash nil (_argHash arg)))
;;
;; We assume Builder.outBasis looks like this:
;;    $(call _outBasis,$C,$A,{outExt},FILE,$(_arg1))
;; where FILE = $(call get,out,$(filter $(_arg1),$(word 1,$(call _expand,{in}))))
;;
(define (_outBasis class arg outExt file arg1)
  &native
  (if (filter arg1 arg)
      (_outBS class arg outExt file)
      (_outBC class arg outExt file arg1)))

(export (native-name _outBX) 1)
(export (native-name _outBS) 1)
(export (native-name _outBasis) 1)


(begin
  ;; test _outBasis

  (define class-exts
    { C: ".o", P: "", PX: "" })

  (define test-files
    { "C[a.c]": ".out/C.c/a.o",
      "File[d/a.c]": "d/a.c",
      "C[d/a.c]": ".out/C.c/d/a.o",
      })

  (define (get-test-file class arg1)
    (cond ((filter "%X" class) nil)
          ((findstring "*" arg1) nil)    ;; indirections are not IDs
          ((filter "%]" arg1) (or (dict-get arg1 test-files)
                                  (error (.. "Unknown ID: " arg1))))
          (else arg1)))

  (define `(t1 id out)
    (define class (word 1 (subst "[" " " id)))
    (define arg (patsubst (.. class "[%]") "%" id))
    (define arg1 (word 1 (_hashGet (_argHash arg))))
    (define `outExt (dict-get class class-exts "%"))
    (define `file (get-test-file class arg1))

    (expect (_outBasis class arg outExt file arg1)
            out))

  ;; C[FILE] (used as an input ID)
  (t1 "C[a.c]"          "C.c/a.c")
  (t1 "C[d/a.c]"        "C.c/d/a.c")
  (t1 "D[d/a.c]"        "D/d/a.c")
  (t1 "C[/.././a]"      "C/_root_/_../_./a")
  (t1 "C@![a.c]"        "C@0@B/a.c")

  ;; C[INSTANCE] (used as an input ID)
  (t1 "P[C[a.c]]"       "P.o_C.c/a.o")
  (t1 "P[C[d/a.c]]"     "P.o_C.c/d/a.o")
  (t1 "P[File[d/a.c]]"  "P.c_/d/a.c") ;; .out = d/a.c

  ;; C[SIMPLE] (NOT an input ID)
  (t1 "X[C[A]]"       "X/C@+A@-")

  ;; C[*VAR] (NOT an input ID)
  (t1 "C[*var]"         "C_@/var")

  ;; C[CLS*VAR] (NOT an input ID)
  (t1 "C[D*var]"        "C_D@/var")
  (t1 "C[D*E*var]"      "C_D@_E@/var")
  (t1 "C[D@E*d/var]"    "C_D@0E@/d/var")

  ;; Complex (arg1 is an input ID)
  (t1 "P[a,b]"          "P_@1,b/a")
  (t1 "P[d/a.c,o=3]"    "P_@1,o@E3.c/d/a.c")
  (t1 "Q[d/a.c,o=3]"    "Q_@1,o@E3/d/a.c")
  (t1 "P[C[d/a.c],o=3]" "P_@1,o@E3.o_C.c/d/a.o")
  (t1 "P[*v,o=3]"       "P_@1,o@E3_@/v")
  (t1 "P[C*v,o=3]"      "P_@1,o@E3_C@/v")

  ;; Complex (arg1 is NOT an input ID)
  (t1 "PX[C[a.c],b]"    "PX_@1,b/C@+a.c@-")
  (t1 "P[x=1,y=2]"      "P_x@E1,y@E2/out")  ;; no unnamed arg

  nil)


;;--------------------------------

(show-exports)
