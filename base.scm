;;----------------------------------------------------------------
;; Utility functions and macros
;;----------------------------------------------------------------

(require "core")
(require "export.scm")

;;--------------------------------
;; Symbols not exported to .mk; minion.mk preamble provides these
;;--------------------------------

;; Defined in minion.mk: \\n \\H [ ] [[ ]] OUTDIR

(define VOUTDIR
  &public
  &native
  ".out/")


(define \H &native &public "#")
(define \n &native &public "\n")
(define \q &native &public "\"")
(set-native "[[" "{")
(set-native "]]" "}")


;; Defined in objects.scm: _self, _class

;; Dynamic state during property evaluation enables `.`, `C`, and `A`:
;;   _self = current instance, bound with `foreach`
;;   _class = current class, bound with `foreach`

(declare _self &native &public)
(declare _class &native &public)

(export-exclude "_self" "_class")

;;--------------------------------
;; Internal and exports functions, macros
;;--------------------------------

;; Construct variable names for memoizaton keys and for the rule cache.
;; Memo values are accessed via `native-value` or `native-call`, so many
;; special characters (e.g. spaces) are okay.
;;
(define `(value-memo-var id) &public (.. "~" id))
(define `(cx-memo-var func) &public (.. "&" func))
(define `(hash-memo-var hash) &public (.. "*h" hash))
(define `(needs-memo-var id) &public (.. "*n" id))
(define `(rulecache-needs-var id) &public (.. "*D-" id))

(define `cx-memo-pat &public (cx-memo-var "%"))


;; Use _info instead of info (SCAM print) for unit testing hook-ability.
(define (_info text)
  &native
  &public
  (print text))


;; Use _eval instead of eval for easy debugging (e.g. minionTrace=_eval)
;; DESC is just for diagnostic purposes.
;;
(define (_eval value ?desc)
  &native
  &public
  (native-eval value))


;; Display an error and halt.  We call this function, instead of `error`, so
;; that is can be dynamically intercepted for testing purposes.
;;
(define (_error msg)
  &native
  &public
  (error msg))


;; Return 1 if A and B are the same.
;;
(define (_eq? a b)
  &native
  &public
  (eq? a b))


;; Return non-nil if VAR has been assigned a value.
;;
(define `(defined? var)
  &public
  ;; "recursive" or "simple" (not "undefined")
  (findstring "s" (native-flavor var)))


(define `(func-defined? name)
  &public
  (filter "r%" (native-flavor name)))


;; Return non-nil if VAR has not been assigned a value.
;;
(define `(undefined? var)
  &public
  (filter "u%" (native-flavor var)))

(define `(recursive? var)
  &public
  (filter "r%" (native-flavor var)))

(define `(simple? var)
  &public
  (filter "s%" (native-flavor var)))


;; Quote VALUE, surrounding with QUOT if it fits on a single-line, or
;; indenting if it's multi-line.  Multi-line values will be prefixed with
;; INDENT.
;;
(define (_qvn value ?quot ?indent)
  &native
  &public
  (if (findstring "\n" value)
      (subst "\n" (.. "\n" indent "  | ") (.. "\n" value))
      (.. quot value quot)))


;; Call _qvn with "'" as QUOT
;;
(define (_qv value)
  &native
  &public
  (_qvn value "'"))


;; Assign a simple variable named NAME to VALUE; return VALUE.
;;
;; When NAME contains `)` or `:`-before-`=` it will cause problems later
;; when using $(call NAME) or $(NAME); see varnames.mk.
;;
;; (native-value NAME) -- `$(value NAME)` in Make -- is the reliable way to
;; access the value.
;;
(define (_set name value)
  &public
  &native
  (native-eval "$1 := $2")
  value)


;; Encode \s and \t as non-space in reversible way
(define `(demote str)
  &public
  (subst "!" "!1" "\t" "!+" " " "!0" str))


;; Reverse demote
(define `(promote str)
  &public
  (subst "!0" " " "!+" "\t" "!1" "!" str))


;; Assign a recursive variable NAME, and return NAME.
;;
;; _fset defines variables that will be reference with $(call NAME,...)  or
;; $(NAME).  VALUE is the function body to be expanded when the variable is
;; referenced.
;;
;; NAME should not contain `)` or `:`-before-`=` because that will cause
;; problems with $(call NAME) or $(NAME); see varnames.mk.
;;
(define (_fset name value)
  &public
  &native

  ;; This prefix preserves leading spaces.  We don't always prepend it
  ;; because it can accumulate as values are copied to other variables.
  (define `begin-value
    (if (filter "1" (word 1 (.. 1 value 0)))
        "$(or )"))

  (native-eval (.. "$1 = " begin-value
                   (subst "\n" "$(\\n)"
                          "#" "$(\\H)"
                          value)))
  name)


;;----------------------------------------------------------------
;; Argument string parsing
;;----------------------------------------------------------------

(define (_argError arg)
  &native
  (_error
   (.. "minion: Argument '" (subst "`" "" arg) "' is mal-formed:\n"
       "   " (subst "`(" " *(*" "`)" " *)* " "`" "" arg) "\n"
       (if (native-var "C")
           (.. "during evaluation of "
               (native-var "C") "(" (native-var "A") ")"))
       "\n\n")))


;; Protect special characters that occur between balanced brackets.
;; To "protect" them we de-nature them (remove the special prefix
;; that identifies them as syntactically significant).
;;
(define (_argGroup arg ?prev)
  &native
  ;; Split at brackets
  (define `a (subst "`(" " `(" "`)" " `)" arg))

  ;; Mark tail of "(..." with extra space
  (define `b (patsubst "`(%" "`(% " a))

  ;; Merge "(..." with immediately following ")", and mark with trailing "`"
  (define `c (subst "  `)" ")` " b))

  ;; Denature delimiters within matched "(...)"
  (define `d (foreach (w c)
               (if (filter "%`" w)
                   ;; Convert specials to ordinary chars & remove trailing "`"
                   (subst "`" "" w)
                   w)))

  (define `e (subst " " "" d))

  (if (findstring "`(" (subst ")" "(" arg))
      (if (findstring arg prev)
          (_argError arg)
          (_argGroup e arg))
      arg))


;; Construct a hash from an argument.  Check for balanced-ness in
;; brackets.  Protect ":" and "," when nested within brackets.
;;
(define (_argHash2 arg)
  &native

  ;; Mark delimiters as special by prefixing with "`"
  (define `(escape str)
    (subst "(" "`(" ")" "`)" "," "`," ":" "`:" str))

  (define `(unescape str)
    (subst "`" "" str))

  (unescape
    (foreach (w (subst "`," " " (_argGroup (escape arg))))
      (.. (if (findstring "`:" w) "" ":") w))))


;; this is not recursive, but it calls a recursive function
(export-varcall "_argHash2" 1)


;; Construct a hash from an instance argument.
;;
(define (_argHash arg)
  &public
  &native
  (define `memo-var (hash-memo-var arg))

  (if (or (findstring "(" arg) (findstring ")" arg) (findstring ":" arg))
      (or (native-value memo-var)
          (_set memo-var (_argHash2 arg)))
      ;; common, fast case
      (.. ":" (subst "," " :" arg))))


;; Get matching values from a hash
;;
(define (_hashGet hash ?key)
  &public
  &native
  (define `pat (.. key ":%"))
  (patsubst pat "%" (filter pat hash)))


;; Describe the definition of variable NAME; prefix all lines with PREFIX
;;
(define (_describeVar name ?prefix)
  &public
  &native
  (.. prefix
      (if (recursive? name)
          (if (findstring "\n" (native-value name))
              (subst "\n" (.. "\n" prefix)
                     (.. "define " name "\n" (native-value name) "\nendef"))
              (.. name " = " (native-value name)))
          (.. name " := " (subst "$" "$$" "\n" "$(\\n)" (native-value name))))))


;;--------------------------------
;; Unit testing utilties
;;--------------------------------


;; _info

(define *info* &public "")

(define (hookInfo value)
  (set *info* (.. *info* value "\n")))

(define `(withInfoHook expr)
  &public
  (let-global ((*info* "")
               (_info hookInfo))
    expr))

;; _error

(define (xsee a b)
  (or (see a b)
      (print "*** Did not see '" a "' in '" b "'")))

(define `(expectInError expr substr)
  &public
  (declare *errors* &public)

  (define `(hookError msg)
    (set *errors* (._. *errors* msg)))

  (let-global ((*errors* "")
               (_error hookError))
    expr
    (expect 1 (xsee substr *errors*))))
