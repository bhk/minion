;;----------------------------------------------------------------
;; Utility functions and macros
;;----------------------------------------------------------------

(require "core")
(require "export.scm")

;;--------------------------------
;; Symbols defined in minion.mk, not exported from Scam-compiled code.
;;--------------------------------

;; Defined in minion.mk: \\n \\H [ ] [[ ]] OUTDIR

(export-text "# base.scm")

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

;;--------------------------------
;; Exported symbols
;;--------------------------------

;; Return non-nil if VAR has been assigned a value.
;;
(define `(defined? var)
  &public
  ;; "recursive" or "simple" (not "undefined")
  (findstring "s" (native-flavor var)))

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


;; Display an error and halt.  We call this function, instead of `error`, so
;; that is can be dynamically intercepted for testing purposes.
;;
(define (_error msg)
  &native
  &public
  (error msg))

(export (native-name _error) 1)


(declare *errorLog* &native &public)

;; Append error message to list
(define (logError msg)
  &public
  (set *errorLog* (._. *errorLog* [msg])))


;; If ID is an instance, return it unmodified.
;;
;; This function does not perform a deep validation of the instance syntax,
;; but it discriminates them from valid indirections, aliases, or file names.
;;
(define `(isInstance id)
  &public
  (filter "%)" id))

(define (_isInstance id)
  &public
  &native
  (isInstance id))

(export (native-name _isInstance) 1)


;; If ID is an indirection (@GROUP, CLASS@GROUP, C1@C2@GROUP, ...) return
;; it unmodified.
;;
(define (_isIndirect id)
  &public
  &native
  (if (findstring "@" id)
      (filter-out "%)" id)))

(export (native-name _isIndirect) 1)


;; Return the alias instance if NAME is a variable name.
;;
(define `(isAlias id)
  ;; Only allow makefile-defined variables to minimize potential for
  ;; confusion with environment and make defaults (e.g. LINT.c !)
  (if (filter "f% o%" (native-origin id))
      (.. "Alias(" id ")")))

(define (_isAlias name)
  &native
  (isAlias name))


(export (native-name _isAlias) 1)


;; If goal NAME is a Minion goal (alias, instance, or indirection), then
;; return an instance that generates a Make rule for it.  The rule must
;; match NAME and ensure that the appropriate Minion goal is built.
;;
;; Otherwise, return empty.
;;
;; This is used by Minion to construct the root set of Minion instances from
;; Make command-line goals.
;;
;; Examples:
;;
;;    "help"     -->  "Alias(help)"
;;    "CC(a.c)"  -->  "_BuildGoal(CC(a.c))"
;;    "@X"       -->  "_BuildGoal(@X)"
;;    "foo"      -->  ""           (presumably a matching Make rule exists)
;;
(define (_buildGoalID name)
  &native
  (if (or (_isInstance name)
          (_isIndirect name))
      (.. "_BuildGoal(" name ")")
      (_isAlias name)))

(export (native-name _buildGoalID) 1)


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

(export (native-name _set) 1)

(begin
  (define `(test key value)
    (_set key value)
    (expect (native-value key) value))
  (test "test_x \ty(" 1)
  (test "test_set" "a\\b#c\\#\\\\$v\nz")
  (test "test$:a=b(" "a\\b#c\\#\\\\$v\nz"))


;;--------------------------------
;; External dependency wrappers: _wildcard, _shell, _var
;;--------------------------------

(define globLog &public "")
(define shellLog &public "")
(define varLog &public "")

;; Same as $(wildcard ...), but keeps a log of patterns matched.
;;
(define (_wildcard globs)
  &public
  &native
  (_set (native-name globLog) (sort (._. globLog globs)))
  (wildcard globs))

(begin
  ;; test _wildcard
  (expect "base.scm" (_wildcard "ba*.scm"))
  (expect "base.scm" (_wildcard "b*e.scm"))
  (expect (sort "ba*.scm b*e.scm") globLog))


;; Encode \s and \t as non-space in reversible way
(define `(demote str)
  &public
  (subst "!" "!1" "\t" "!+" " " "!0" str))


;; Reverse demote
(define `(promote str)
  &public
  (subst "!0" " " "!+" "\t" "!1" "!" str))


;; Same as $(shell ...), but logs commands issues.
;;
(define (_shell command)
  &public
  &native
  (_set (native-name shellLog) (sort (._. shellLog (demote command))))
  (shell command))

(begin
  ;; test _shell
  (expect "base.scm" (_shell "echo ba*.scm"))
  (expect "base.scm" (_shell "echo b*.scm"))
  (expect "echo ba*.scm" (promote (word 2 shellLog))))


(define (_var name)
  &public
  &native
  (_set (native-name varLog) (sort (._. varLog name)))
  (native-var name))

(begin
  ;; test _shell
  (define VFOO &native 1)
  (define VBAR &native 2)
  (expect "1" (_var "VFOO"))
  (expect "2" (_var "VBAR"))
  (expect "VBAR VFOO" varLog))


(export (native-name _wildcard) 1)
(export (native-name _shell) 1)
(export (native-name _var) 1)


;; Return the variable portion of indirection ID.  Return nil if the ID ends
;; in @.
;;
;;    @VAR, C@VAR, D@C@VAR  -->  VAR, VAR, VAR
;;
(define (_ivar id)
  &native
  (filter-out "%@" (subst "@" "@ " id)))

(export (native-name _ivar) 1)


(define (_EI id where)
  &native

  (_error
   (..
    (if (filter "%@" id)
        (.. "Invalid target (ends in '@'): " id)
        (.. "Indirection '" id "' references undefined variable '" (_ivar id) "'"))
    (if where
        (.. "\nFound while expanding "
            (if (filter "_BuildGoal(%" where)
                "command line goal"
                where))))))

(export (native-name _EI) 1)


;; WHERE = where LIST came from, e.g. "C(A).P or variable name
;;
(define (_expandX list where)
  &native
  (define `(expand var indir)
    (if (findstring "*" var)
        (_wildcard var)
        (if (undefined? var)
            (_EI indir where)
            (_expandX (native-var var) var))))

  ;; Create a pattern for indirection expansion
  ;;      @var   ==>   %
  ;;     C@var   ==>   C(%)
  ;;   D@C@var   ==>   D(C(%))
  (define `(ipat ref)
    (if (filter "@%" ref)
        "%"
        (subst " " ""
               (filter "%( %% )"
                       (.. (subst "@" "( " ref) " % " (subst "@" " ) " ref))))))

  (foreach (w list)
    (or (isInstance w)
        ;; after ruling out instances, "@" means indirection
        (if (findstring "@" w)
            (foreach (v (or (_ivar w) "=@"))
              (patsubst "%" (ipat w) (expand v w)))
            (or (isAlias w)
                w)))))

(export (native-name _expandX) nil)


;; Expand indirections in LIST, and translate bare alias names to instances.
;;
;; PROP is used in reporting "Found while expanding C(A).PROP" errors
;;
(define (_expand list ?prop)
  &native
  &public
  (_expandX list (.. _self "." prop)))

(export (native-name _expand) nil)


(begin
  ;; test _expand
  (set-native-fn "ev0" "")
  (set-native-fn "ev1" "a1 b1")
  (set-native-fn "ev2" "a2 @ev1 c@ev1 c(@v) D@C@ev1 E@ev0")
  (expect (_expand "E@ev0") "")
  (expect (_expand "a @ev2")
          "a a2 a1 b1 c(a1) c(b1) c(@v) D(C(a1)) D(C(b1))")

  (let-global ((_error logError)
               (*errorLog* nil)
               (_self "C(A)"))
    (expect "" (_expand "a@" "x"))
    (expect "" (_expand "a@undef" "x"))
    (expect 1 (see "Invalid target" (first *errorLog*)))
    (expect 1 (see "Found while expanding C(A).x" (first *errorLog*)))
    (expect 1 (see "undefined variable 'undef'" (nth 2 *errorLog*)))
    (expect "minion.md minion.mk" (_expand "@minion.m*"))
    nil)

  nil)


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
  (define `protect
    (if (filter "1" (word 1 (.. 1 value 0)))
        "$(or )"))

  (native-eval (.. "$1 = " protect
                   (subst "\n" "$(\\n)"
                          "#" "$(\\H)"
                          value)))
  name)

(begin
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
  (test "test_f" "a\\b\\\\c\\#\\"))

(export (native-name _fset) 1)

;; Return value of VAR, evaluating it only the first time.
;;
(define (_once var)
  &native
  (define `cacheVar (.. "_o~" var))

  (if (undefined? cacheVar)
      (_set cacheVar (native-var var))
      (native-value cacheVar)))

(export (native-name _once) nil)

(begin
  ;; test _once
  (native-eval "fv = 1")
  (native-eval "ff = $(fv)")
  (expect 1 (_once "ff"))
  (native-eval "fv = 2")
  (expect 2 (native-var "ff"))
  (expect 1 (_once "ff")))


;;----------------------------------------------------------------
;; Argument string parsing
;;----------------------------------------------------------------

(define (_argError arg)
  &native
  (_error
   (.. "Argument '" (subst "`" "" arg) "' is mal-formed:\n"
       "   " (subst "`(" " *(*" "`)" " *)* " "`" "" arg) "\n"
       (if (native-var "C")
           (.. "during evaluation of "
               (native-var "C") "(" (native-var "A") ")")))))

(export (native-name _argError) 1)


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

(export (native-name _argGroup) nil)


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

(export (native-name _argHash2) 1)


;; Construct a hash from an instance argument.
;;
(define (_argHash arg)
  &public
  &native
  (define `memo-var (.. "_h~" arg))

  (if (or (findstring "(" arg) (findstring ")" arg) (findstring ":" arg))
      (or (native-value memo-var)
          (_set memo-var (_argHash2 arg)))
      ;; common, fast case
      (.. ":" (subst "," " :" arg))))

(export (native-name _argHash) 1)


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


;; Get matching values from a hash
;;
(define (_hashGet hash ?key)
  &public
  &native
  (define `pat (.. key ":%"))
  (patsubst pat "%" (filter pat hash)))

(export (native-name _hashGet) nil)


(expect (_hashGet ":a :b x:y" "") "a b")
(expect (_hashGet ":a :b x:y" "x") "y")


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

(export (native-name _describeVar) nil)

(begin
  (set-native "sv-s" "a\nb$")
  (set-native-fn "sv-r1" "a b")
  (set-native-fn "sv-r2" "a\nb")

  (expect (_describeVar "sv-s" "P: ")  "P: sv-s := a$(\\n)b$$")
  (expect (_describeVar "sv-r1" "P: ")  "P: sv-r1 = a b")
  (expect (_describeVar "sv-r2" "P: ")  (.. "P: define sv-r2\n"
                                            "P: a\n"
                                            "P: b\n"
                                            "P: endef")))
