;;----------------------------------------------------------------
;; Object system
;;----------------------------------------------------------------
;;
;; Property evaluation makes use of memoization and compilation:
;;    - Property definitions are compiled before evaluation (see _cx).
;;    - Property compilation is memoized at two locations:
;;        &C.P for first definition found for C
;;        &CHP.P for definitions found via {inherit}
;;    - Property evaluation is memoized (per instance & property)
;;

(require "core")
(require "export.scm")
(require "base.scm")


(define `(func-defined? name)
  (filter "r%" (native-flavor name)))


;; Report error: mal-formed instance name
;;
(define (_E0)
  &native
  (define `reason
    (if (filter "(%" _self)
        "no CLASS before '('"
        (if (findstring "(" _self)
            "no ')' at end"
            "unbalanced ')'")))

  (_error (.. "Mal-formed target '" _self "'; " reason)))


;; Validate ID and return its class.
;;
;; If ID is a well-formed instance -- CLASS(..) -- return CLASS.
;; If ID is a plain file name -- no "(" or ")" -- return "_File(ID)".
;; If ID is mal-formed -- has no "(", does not end in ")", or CLASS is empty,
;;   report an error.
;;
(define `(idClass id)
  (if (findstring "(" id)
      (or (filter-out "|%" (subst "(" " |" (filter "%)" id)))
          (_E0))
      (if (findstring ")" id)
          (_E0)
          "_File")))

(let-global ((_error "-"))
  (expect (idClass "f") "_File")
  (expect (idClass "C(a)") "C")
  (expect (idClass "(a)") "-")
  (expect (idClass "C(a") "-")
  (expect (idClass "Ca)") "-")
  (expect (idClass "Ca)b") "-")
  (expect (idClass "C(a)b") "-"))


;; Return the class portion of a well-formed instance, or nil if ID contains
;; no "(".
;;
(define (_idC id)
  &native
  (if (findstring "(" id)
      (word 1 (subst "(" " " id))))


;; True when ID -- which must be an instance -- has an invalid class name.
;;
(define (_isClassInvalid id)
  &public
  &native
  (undefined? (.. (_idC id) ".inherit")))


;; Chain positions (CHP): a chain position describes the state of iteration
;; through the inheritance chain.  It is a list of zero or more classes, or
;; a single instance name.  Chain positions are single words (the current
;; class) unless multiple inheritance is encountered.
;;
;;  (word 1 CHP) = current class
;;  (_chp+ CHP) = next CHP in inheritance chain; nil => done
;;

;; Return the next chain position in the inheritance search space.
;;
(define (_chp+ chp)
  &native
  ;; Here filter-out removes the first name in CHP and stips extraneous
  ;; spaces from the result.
  (if (filter "%)" chp)
      (_idC chp)
      (filter-out
       "=%" (.. (native-var (.. (word 1 chp) ".inherit")) " =" chp))))


;; Return find the first definition of P in CHP.  The result might be CHP or
;; some ancestor of CHP, or nil if there is no definition.
;;
(define (_walk p chp)
  &native
  (define `C1 (word 1 chp))
  (if chp
      (if (defined? (.. C1 "." p))
          chp
          (_walk p (_chp+ chp)))))


(define (_hasProperty p id)
  &native
  (if (or (defined? (.. id "." p))
          (_walk p (filter-out " |%" (subst "(" " |" id))))
      1))


;; Construct an E1 (undefined property) error message.
;;
;; PROP = the property that was not found
;; SITE & CALLER identify one of the two ways in which E1 might be called:
;;  1) From `_cx`, during compilation of an `{inherit}` constrict
;;        SITE = source function for definition
;;        CALLER = nil
;;  2) From `.` at "run time"; CALLER = $0 of caller of `.` (if supplied)
;;        SITE = nil
;;        CALLER is one of:
;;          &C.P : function memoized at class level
;;          &CHP.P : function memoized at CHP level (after processing inherit)
;;          &I.P : function generated for instance property definition
;;          other : whatever user passed to `.`
;;
(define `(e1-msg prop caller site)
  ;; extract source variable in case of "&..." caller
  (define `caller-prop (lastword (subst "." ". " caller)))
  (define `caller-class (patsubst cx-memo-pat "%" (word 1 (subst "." " ." caller))))
  (define `caller-src (.. (word 1 (_walk caller-prop caller-class)) "." caller-prop))

  ;; If PROP differs from SITE, then {inherit PROP} was used.
  (define `inherit-arg (if (findstring (.. "." prop "=") (.. site "=")) "" (.. " " prop)))

  ;; original definition (source) variable that referenced PROP
  (define `src-var
    (cond (site site)
          ((filter cx-memo-pat caller) caller-src)
          (else caller)))

  (define `src-type
    (cond (site (.. " by {inherit" inherit-arg "} in"))
          (caller " from")))

  (define `src-desc
    (if (or site caller)
        (.. ":\n" (_describeVar src-var "   "))))

  (.. "Undefined property {" prop "} for " _self
      " was referenced" src-type src-desc
      ;; point out potentially bogus class
      (if (undefined? (.. _class ".inherit"))
          (.. "\n NOTE: " _class ".inherit is not defined!\n"))))


;; _E1: display undefined property error and throw error
;;
(define (_E1 p caller site)
  &native
  (_error (e1-msg p caller site)))


(define `(ewalk p chp caller ?site)
  (or (_walk p chp)
      (_E1 p caller site)))


(declare (_cxMemo p chp) &native)


;; Compile an inherited property definition, returning the memoized object
;; function name.
;;
;; P = property to compile
;; CHP = chain position *above which* we will search
;; SRC-VAR = the property definition inheriting P
;;
(define (_cxInherit p chp src-var)
  &native
  (_cxMemo p (ewalk p (_chp+ chp) nil src-var)))


;; See _cxDef.
;;
(define (_cxTok tokens p chp src-var)
  &native

  (define `(iprop tok)
    (if (filter "{inherit}" tok)
        p
        (patsubst "{inherit!0%}" "%" tok)))

  ;; expand {inherit} and {inherit NAME} expressions
  (define `stage1
    (if (findstring "{inherit" tokens)
        (foreach (tok tokens)
          (if (filter "{inherit} {inherit!0%}" tok)
              (.. "$(call!0"
                  (subst " " "!0" (_cxInherit (iprop tok) chp src-var))
                  ")")
              tok))
        tokens))

  ;; expand {PROP} expressions
  (patsubst "{%}" "$(call!0.,%,$0)" stage1))


;; Compile a property definition, returning a function body.
;;
;; SRC = text of function definition
;; P = name of property being compiled
;; CHP = chain position at which SRC-VAR was found
;; SRC-VAR = variable from which SRC was obtained
;;
(define `(cxDefn src p chp src-var)
  ;; convert string to list of tokens for parsing {WORD} expressions
  (define `(tokenize src)
    (subst "{" " {"
           "}" "} "
           "(" " ( "
           ")" " ) "
           "," " , "
           "!0" "!0 "
           "{inherit!0 " "{inherit!0"
           (demote src)))

  (define `(untokenize tokens)
    (promote (subst " " "" tokens)))

  (if (findstring "{" src)
      (untokenize (_cxTok (tokenize src) p chp src-var))
      src))


(let-global ((_cxInherit
              (lambda (p chp sv)
                (.. "&" chp "Base." p))))

  (expect "$(call .,FOO,$0)" (cxDefn "{FOO}" "P" "CC" "CC.P"))
  (expect "$(call &CCBase.P)" (cxDefn "{inherit}" "P" "CC" "CC.P"))
  (expect "$(call &CCBase.X)" (cxDefn "{inherit X}" "P" "CC" "CC.P"))
  (expect " { FOO }  {(} {a)} " (cxDefn " { FOO }  {(} {a)} " "P" "CC" "CC.I")))


;; Compile a Minion property definition, returning a function body.
;;
;; P = property name
;; CHP = a chain position at which a property definition has been found.
;;
(define (_cx p chp)
  &native
  ;; performant var binding
  (foreach (src-var (.. (word 1 chp) "." p))
    (define `src
      (native-value src-var))
    (if (simple? src-var)
        (subst "$" "$$" src)
        (cxDefn src p chp src-var))))


(define (_cxMemo p chp)
  &native
  (define `memo-var (cx-memo-var (.. chp "." p)))
  (if (func-defined? memo-var)
      memo-var
      (_fset memo-var (_cx p chp))))


;; Evaluate property P for current instance (given by dynamic _class and A)
;; and cache the result.
;;
;; CALLER = the function/variable that is calling `.`
;;
;; Performance notes:
;;  * memoization avoids exponential times
;;  * Value memo hit rate is about 50% for med-to-large projects
;;  * CX memo hit rate approaches 100% in large projects
;;  * We cannot directly "call" variables with ")" in their name, due
;;    to a quirk of Make.
;;
(define (. p ?caller)
  &native

  (define `I.P (.. _self "." p))
  (define `value-var (value-memo-var I.P))
  (define `cx-var (cx-memo-var (.. _class "." p)))

  (define `value
    (if (defined? I.P)
        ;; directly expand without writing I.P definition to var
        (foreach (dollar0 (cx-memo-var I.P))
          (native-call "or" (_cx p _self)))
        ;; memoize compilation at C.P
        (native-call (if (func-defined? cx-var)
                         cx-var
                         (_fset cx-var (_cx p (ewalk p _class caller)))))))

  (if (simple? value-var)
      (native-value value-var)
      (_set value-var value)))


;; Evaluate property for one or more IDs (instances or plain file
;; names). Result is all property values, space-delimited, one per ID.
;;
;; If an ID is a plain file, treat it as `_File(ID)`.
;; If an ID is mal-formed, report the mal-formed instance and error.
;;
(define (get p ids)
  &public
  &native
  (foreach (_self ids)
    (foreach (_class (idClass _self))
      (. p))))


(define `argText
  &public
  (patsubst (.. _class "(%)") "%" _self))

(define (_argText)
  &native
  argText)
(declare _argText &native) ;; re-define so it can be referenced as a variable

(define (_args)
  &native
  (_hashGet (_argHash argText)))
(declare _args &native)

(define (_arg1)
  &native
  (word 1 _args))
(declare _arg1 &native)

(define (_namedArgs key)
  &native
  (_hashGet (_argHash argText) key))

(define (_namedArg1 key)
  &native
  (word 1 (_namedArgs key)))

;;--------------------------------
;; describeDefn
;;--------------------------------

;; Like `_chp+`, but also handles initial "C(A)" -> "C" inheritance step.
;;
(define `(pup0 id-or-chp)
  (or (_idC id-or-chp)
      (_chp+ id-or-chp)))


(define (_describeProp chp prop)
  &native
  (define `(recur)
    (_describeProp (pup0 chp) prop))

  (define `C1.P
    (.. (word 1 chp) "." prop))

  (define `has-inherit
    (and (recursive? C1.P)
         (findstring "{inherit}" (native-value C1.P))))

  (if chp
      (if (undefined? C1.P)
          (recur)
          (.. (_describeVar C1.P "   ")
              (if has-inherit
                  (.. "\n\n...wherein {inherit} references:\n\n" (recur)))))))


;; Return inheritance chain (a list of all the classes that will be
;; searched, in order) for CHP (zero or more classes).
;;
(define (_chain chp ?seen)
  &native
  (if chp
      (_chain (_chp+ chp) (._. seen (word 1 chp)))
      (strip seen)))


;; Warn when a Make automatic variable is evaluatied.
;;
;; AUTO = auto var: "@", "<", or "^"
;; FN = $0 at time of reference
;;
(define (_badAuto auto fn)
  &native

  (define `where
    (if (filter cx-memo-pat fn)
        ;; compiled function
        (word 1 (patsubst cx-memo-pat "%" fn))
        ;; some other function
        (.. "$(call " fn ",...)")))

  (_error (.. "$$" auto " was evaluated prior to rule processing\n"
              "during evaluation of " where (if _self (.. " in context of " _self)))))


;;--------------------------------
;; Exports
;;--------------------------------

(export-modify-foreach "." "0")
(export-modify-foreach "get" "_self _class")

;;--------------------------------
;; Tests
;;--------------------------------

(set-native-fn "A.inherit" "")
(set-native-fn "A.class" "$(_class)")
(set-native-fn "A.self"  "$(_self)")
(set-native-fn "A.y" "Y")
(set-native-fn "A.ia" "A.ia")

(set-native-fn "Mixin.inherit" "")
(set-native-fn "Mixin.m" "Mixin.m")
(set-native-fn "Mixin.icm" "Mixin.icm + {inherit}")

(set-native-fn "B.inherit" "A")
(set-native-fn "B.icm" "B.icm")
(set-native-fn "B.m" "B.m + {inherit}")
(set-native-fn "B.y" "B.y")

(set-native-fn "C.inherit" "Mixin B")
(set-native-fn "C.z" "<C.z>")
(set-native-fn "C.icm" "C.icm + {inherit}")
(set-native-fn "C.iname" "C.iname + {inherit m}")

(set-native    "C(a).s" "C(a).s:$0 $$ {x}")        ;; simple instance prop
(set-native-fn "C(a).r" "C(a).r:$0 $$ {class}")    ;; recursive instance prop
(set-native-fn "C(a).ia" "C(a).ia + {inherit}")    ;; recursive w/ {inherit}
(set-native-fn "C(a).icm" "C(a).icm + {inherit}")  ;; recursive w/ {inherit}


;; _chain, chp+, _walk
(expect (_chain "C(a)") "C(a) C Mixin B A")
(expect (_chp+ "C") "Mixin B")
(expect (_chp+ "Mixin B") "B")
(expect (_walk "z" "C") "C")
(expect (_walk "m" "C") "Mixin B")

;; _hasProperty
(expect (_hasProperty "m" "C(a)") 1)
(expect (_hasProperty "un" "C(a)") nil)


;; get, `.`

;; instance property
(expect (get "r" "C(a)") "C(a).r:&C(a).r $ C")  ;; no extra expansion
(expect (native-flavor "~C(a).r") "simple")
;; note: native-var will not work only because of GNU Make mis-parsing
;; the $(VAR) expression when VAR contains parens.
(expect (native-value "~C(a).r") "C(a).r:&C(a).r $ C")  ;; memo saved
(set-native "~C(a).r" "-") ;; swap memo
(expect (get "r" "C(a)") "-")  ;; memo is used

;; *simple* instance property
(expect (get "s" "C(a)")  "C(a).s:$0 $$ {x}")       ;; no extra expansion

;; class property
(expect (get "z" "C(a)") "<C.z>")
(expect (native-flavor "&C.z") "recursive")
(expect (native-value "&C.z") "<C.z>")
(set-native-fn "&C.z" "ZAP")
(expect (get "z" "C(b)") "ZAP")  ;; C(a).z is value-cached...

;; base class property
(expect (get "y" "C(a)") "B.y")
(expect (native-value "&C.y") "B.y")  ;; populates memo at class level

;; {inherit} from instance property
(expect (get "ia" "C(a)") "C(a).ia + A.ia")
(expect (native-value "&A.ia") "A.ia")

;; {inherit} from instance property defined in complex CHP
(begin
  (get "icm" "C(a)")
  (expect (native-value "&C.icm") "C.icm + $(call &Mixin B.icm)")
  (expect (native-value "&C.icm") "C.icm + $(call &Mixin B.icm)")
  (expect (native-value "&Mixin B.icm") "Mixin.icm + $(call &B.icm)")
  (expect (get "icm" "C(a)") "C(a).icm + C.icm + Mixin.icm + B.icm"))

;; {inherit} from a class property w/ complex CHP
(expect (get "iname" "C(a)") "C.iname + Mixin.m")
(expect (native-value "&C.iname") "C.iname + $(call &Mixin B.m)")
(expect (native-value "&Mixin B.m") "Mixin.m")

;; _File(PLAIN) defaulting ... note _self does *not* reflect _File(xxx), but
;; that only affects the _File class itself.  $(_argText) seems to reflect
;; PLAIN.
(set-native-fn "_File.id" "$(_class)($(_argText))")
(expect (get "id" "f") "_File(f)")
(export-exclude "_File.id")

;; _E0 errors

(define (xsee a b)
  (or (see a b)
      (print "*** Did not see '" a "' in '" b "'")))

(define `(expect-error expr value error-content)
  (let-global ((_error logError)
               (*errorLog* nil))
    (expect expr value)
    (expect 1 (xsee error-content (first *errorLog*)))))

(expect-error (get "p" "(a)") nil
               "'(a)'; no CLASS")

(expect-error (get "p" "C(a") nil
              "'C(a'; no ')'")

(expect-error (get "p" "C(a)b") nil
              "'C(a)b'; no ')' at end")

(expect-error (get "p" "Ca)") nil
              "'Ca)'; unbalanced ')'")

;; _E1 errors

;; _e1-msg caller/site descriptions
(let-global ((_self "C(a)")
             (_class "C"))
  ;; site
  (expect 1 (see (.. "Undefined property {y} for C(a) was referenced "
                     "by {inherit} in:\n   A.y = Y")
                 (e1-msg "y" nil "A.y")))
  ;; caller is &C.P memo of C.P
  (expect 1 (see "from:\n   C.z =" (e1-msg "p" "&C.z" nil)))
  ;; caller is &C.P memo of inherited prop
  (expect 1 (see "{p} for C(a) was referenced from:\n   B.y =" (e1-msg "p" "&C.y" nil)))
  ;; caller is complex &CHP.P
  (expect 1 (see "from:\n   Mixin.m =" (e1-msg "p" "&Mixin B.m" nil)))
  ;; caller is &I.P
  (expect 1 (see "from:\n   C(a).r =" (e1-msg "p" "C(a).r" nil)))
  ;; caller is OTHER
  (expect 1 (see "from:\n   _shell =" (e1-msg "p" "_shell" nil)))
  ;; bad class?
  (let-global ((_class "CX"))
    (expect 1 (see "CX.inherit is not defined" (e1-msg "p" "foo" nil)))))

(expect-error (get "unk" "C(a)") nil
              "Undefined property {unk} for C(a)")

(set-native-fn "C.e1" "{inherit}")
(expect-error (get "e1" "C(a)") nil
              (.. "Undefined property {e1} for C(a) was referenced "
                  "by {inherit} in:\n   C.e1 = {inherit}"))

(set-native-fn "C(a).e2" "{inherit UNK}")
(expect-error (get "e2" "C(a)") nil
              (.. "Undefined property {UNK} for C(a) was referenced by "
                  "{inherit UNK} in:\n   C(a).e2 = {inherit UNK}"))

(set-native-fn "C.eu" "{undef}")
(expect-error (get "eu" "C(a)") nil
              (.. "Undefined property {undef} for C(a) was referenced from:\n"
                  "   C.eu = {undef}"))

;; _describeProp

(expect (_describeProp "C(a)" "icm")
        (.. "   C(a).icm = C(a).icm + {inherit}\n"
            "\n"
            "...wherein {inherit} references:\n"
            "\n"
            "   C.icm = C.icm + {inherit}\n"
            "\n"
            "...wherein {inherit} references:\n"
            "\n"
            "   Mixin.icm = Mixin.icm + {inherit}\n"
            "\n"
            "...wherein {inherit} references:\n"
            "\n"
            "   B.icm = B.icm"))

(expect (_describeProp "UNDEF(a)" "foo") "")

;; _badAuto
(set-native-fn "BA" "$(call _badAuto,@,$0)")
(set-native-fn "C(a).w0" "$(BA)")
(set-native-fn "C.w1" "$(BA)")
(set-native-fn "C.w2" "$(call BA)")

(expect-error (get "w0" "C(a)") nil
              (.. "$$@ was evaluated prior to rule processing\nduring "
                  "evaluation of C(a).w0 in context of C(a)"))
(expect-error (get "w1" "C(a)") nil
              "evaluation of C.w1 in context of C(a)")
(expect-error (get "w2" "C(a)") nil
              "evaluation of $(call BA,...) in context of C(a)")
