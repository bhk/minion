;;------------------------------------------------------------------------
;; Compile property definitions
;;
;; This module deals with compilation of Minion syntax, and not with
;; details of the inheritance model.  Its declares but does not
;; define _cxInherit.
;;
;; It generates target code that references `get` and `.`.
;;
;;------------------------------------------------------------------------

(require "core")
(require "base.scm")


;; External dependencies
(declare (_cxInherit p chp src-var) &native)


(define `(contains-either a b str)
  (findstring a (subst b a str)))


;; convert arbitrary string to bang-encoding
(define (_cxD s) &native (subst "!" "!1" " " "!0" "\t" "!+" s))

;; recover arbitrary string from bang-encoding
(define (_cxU s) &native (subst "!+" "\t" "!0" " " "!1" "!" s))


;; mark these characters as syntactically significant
(define `(tokenize text)
  (subst
   "." "!@."
   "," "!@,"
   "(" "!@("
   ")" "!@)"
   "{" "!@{"
   "}" "!@}"
   (_cxD text)))


(define `(detokenize obj)
  (_cxU (subst " " ""
               "!@" ""
               obj)))


(define `(cxbErrorMsg why what where prop)
  (define `reasons
    { UP: "Unbalanced parentheses within {...}",
      UB: "Unbalanced \"{\" or \"}\" in definition",
      G1: "Empty ID or PROP in {ID.PROP}",
      G2: "Too many \".\" characters in {ID.PROP}",
      IN: "Unexpected characters in {inherit...}" });

  (define `reason
    (subst "@" (detokenize what)
           (_cxU (subst (.. why "!=%") "%"
                        (filter (.. why "%") reasons)))))

  ;; Subexpressions in WHAT may have already been expanded, which would make
  ;; it more confusing than helpful.
  (define `showWhat
      (if (findstring what (native-value where))
          (.. "at: " what "\n")))

  (.. "minion: Error in property definition\n"
      "\n"
      reason "\n"
      showWhat
      "in: " where "\n"
      "when evaluating: " _self "." prop "\n\n"))


;; _cxbError: display undefined property error and throw error
;;
(define (_cxbError why what where prop)
  &native
  (_error (cxbErrorMsg why what where prop)))


;;------------------------------------------------------------------------
;; _cxNest: sanitize parentheses
;;------------------------------------------------------------------------

;; OBJ = non-empty object string split into words at "(..." and "...)"
;; Return nil if parens are unbalanced; sanitized string otherwise.
;;
(define (_cxNest2 obj)
  &native

  (define `DONE
    (word 1 obj))
  (define `RECUR
    (_cxNest2
     (subst " " ""
            "!@(" " !@("
            "!@)" "!@) "
            (foreach (w obj)
              (if (filter "!@(%!@)" w)
                  (.. " " (subst "!@" "" w) " ")
                  w)))))

  (if (filter "!@(%!@)" obj)
      RECUR
      (if (contains-either "!@(" "!@)" obj)
          nil
          DONE)))


;; Convert tokens in "(...)" to literal characters.
;; Escape "," outside of parens.
;; Error on unbalanced parens.
;;
(define (_cxNest obj)
  &native

  (if (findstring "!@" obj)
      (subst "!@," "$;"
             (_cxNest2 (subst "!@(" " !@("
                                 "!@)" "!@) "
                                 obj)))
      obj))


;;------------------------------------------------------------------------
;; Level 3: computed {PROP} and {ID.P}, validation of nested expressions
;;------------------------------------------------------------------------

(define (_cxb3 obj prop chp src-var)
  &native

  (define `(E why what)
    (_cxbError why what src-var prop))

  (define `(RECUR)
    (define `obj
      (foreach (w obj)
        (or (filter-out "!@{%!@}" w)
            (foreach (text (or (_cxNest (patsubst "!@{%!@}" "%" w))
                               (E "UP" w)))
              (define `id (word 1 (subst "!@." " " text)))
              (define `p (word 2 (subst "!@." " " text)))
              (if (findstring "!@." text)
                  ;; {ID.PROP} -> get
                  (cond
                   ((filter "!@.% %!@." text) (E "G1" w))
                   ((word 3 (subst "!@." ". ." text)) (E "G2" w))
                   (else (.. "$(call!0get," p "," id ")")))
                  ;; {PROP} -> .
                  (.. "$(call!0.,"  text ",$0)"))))))
    (define `obj
      (subst " " ""
             "!@{" " !@{"
             "!@}" "!@} "
             obj))
    (_cxb3 obj prop chp src-var))

  (if (filter "!@{%!@}" obj)
      (RECUR)
      (if (contains-either "!@{" "!@}" obj)
          (E "UB" obj)
          obj)))


;;------------------------------------------------------------------------
;; Level 2:  {inherit} and {inherit NAME}
;;------------------------------------------------------------------------

(define (_cxb2 objIn prop chp src-var)
  &native

  (define `(next)
    ;; validate and rewrite {inherit} and {inherit NAME}
    (define `obj (subst " " "" "!@{" " !@{" "!@}" "!@} " objIn))

    (define `obj
      (foreach (w obj)
        (define `name
          (if (filter "!@{inherit!@}" w)
              (_cxD prop)
              ;; ! => space, tab, paren, comma, brace, period
              (if (findstring "!" (or (patsubst "!@{inherit!0%!@}" "%" w) "!"))
                  (_cxbError "IN" w src-var prop)
                  (patsubst "!@{inherit!0%!@}" "%" w))))
        (if (filter "!@{inherit!@} !@{inherit!0%!@}" w)
            (.. "$(call!0" (_cxD (_cxInherit name chp src-var)) ")")
            w)))
    (_cxb3 obj prop chp src-var))

  (if (contains-either "!@{" "!@}" objIn)
      (next)
      objIn))


;;------------------------------------------------------------------------
;; Level 1:  {}, {NAME}, escaping of { and }
;;------------------------------------------------------------------------

(define (_cxb1 text prop chp src-var)
  &native

  ;; tokenize for innermost {NAME} replacement
  (define `obj
    (subst
     ;; escape braces
     "$$" "$$ "   ;; note: leaves spare space after literal $$
     "$!@{" "{"
     "$!@}" "}"
     "!@{!0" "{!0"
     "!0!@}"  "!0}"
     (tokenize text)))

  ;; {}
  (define `obj (subst "!@{!@}" "$(_self)" obj))

  ;; rewrite simple {NAME}, excluding non-NAME chars and {inherit}
  (define `obj (subst "!" " !" " !@}" "!@} " obj))
  (define `obj (subst "!@{inherit!" "!@{inherit !" obj))
  (define `obj (patsubst "!@{%!@}" "$(call!0.,%,$0)" obj))

  (define `obj (_cxb2 obj prop chp src-var))

  ;; reverse tokenization
  (detokenize obj))


;; Compile a property definition, returning a function body.
;;
;; SRC = text of function definition
;; PROP = name of property being compiled
;; CHP = chain position at which SRC-VAR was found
;; SRC-VAR = variable from which SRC was obtained
;;
(define `(cxBody src prop chp src-var)
  &public
  ;; convert string to list of tokens for parsing {WORD} expressions
  (if (contains-either "{" "}" src)
      (_cxb1 src prop chp src-var)
      src))
