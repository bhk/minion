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
(require "compile.scm")


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
  &public
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
  &public
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
        (cxBody src p chp src-var))))


(define (_cxMemo p chp)
  &native
  (define `memo-var (cx-memo-var (.. chp "." p)))
  (if (func-defined? memo-var)
      memo-var
      (_fset memo-var (_cx p chp))))


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

;; TODO: now chp+ does!
;; Like `_chp+`, but also handles initial "C(A)" -> "C" inheritance step.
;;
(define `(pup0 id-or-chp)
  (or (_idC id-or-chp)
      (_chp+ id-or-chp)))


;; TODO: move to help?  (test elsewhere?)
(define (_describeProp chp prop)
  &native
  &public
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
  &public
  (if chp
      (_chain (_chp+ chp) (._. seen (word 1 chp)))
      (strip seen)))


;;--------------------------------
;; _badAuto
;;--------------------------------

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
