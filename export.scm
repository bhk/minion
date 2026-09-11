;;----------------------------------------------------------------
;; Facililities for "exporting" functions to Minion
;;----------------------------------------------------------------

(require "core")

(define export-patterns "_% . get")

(define *export-excludes* "")
(define *export-varcalls* "")

;; Exclude NAMES from automatic export.
;;
(define (export-exclude ...names)
  &public
  (set *export-excludes* (._. *export-excludes* (promote names))))

;; Declare that NAME is a safe varcall when called with NARGS.
;;
(define (export-varcall name nargs)
  &public
  (set *export-varcalls* (._. *export-varcalls* {=name: nargs})))


;;----------------------------------------------------------------
;; The ridiculous varcalls optimization!
;;
;; In GNU Make, calling a variable as a function is much like expanding that
;; variable.  The only difference is that calling the function binds
;; arguments to $1, $2, etc. whereas $(NAME) sees the caller's arguments.
;; As a result, $(NAME) will yield the same results as $(call
;; NAME,$1,$2,...,$N), where N is the number of arguments used in NAME, but
;; faster.  We can replace $(call NANE,...) expressions with $(NAME) except
;; in the following cases:
;;
;;   a) If NAME is re-entrant, $(NAME) will trigger a fatal make error.
;;   b) If the call site does not pass enough arguments, NAME will see
;;      values other than nil for the unspecified arguments.
;;
;; We allow the user to specify known-safe functions, but we try to infer
;; the re-entrancy for almost all functions by examining their call
;; expressions.  Any leaf function is re-entrant.  More generally, any
;; function calling only known-safe functions is non-reentrant.  Since this
;; definition is recursive, we repeat the analysis until the set of known
;; safe functions stabilizes.
;;----------------------------------------------------------------


(define (highest-arg src)
  (or (lastword (foreach (n "1 2 3 4 5 6 7 8 9")
                  (if (findstring (.. "$" n) src) n)))
      0))

(define (get-called-functions code)
  (patsubst "$(call!0%" "%"
            (filter "$(call!0%"
                    (subst "$(c" " $(c"
                           "," " ,"
                           ")" " )" [code]))))

(expect "a b" (get-called-functions "zxc$(call a)qwer$(call b,$1,$2)er"))

(define (get-varcalls-with names known safe-names)
  (strip
   (foreach (name names)
     (define `code (native-value name))
     (or (dict-find name known)
         (if (filter-out safe-names (get-called-functions code))
             nil
             {=name: (highest-arg code)})))))

;; Look for safe varcalls, given known safe ones, and iterate until
;; the set doesn't grow.
(define (get-varcalls-loop names known)
  (let ((vc-prev known)
        (vc-now (get-varcalls-with names known (dict-keys known))))
    (if (eq? vc-prev vc-now)
        vc-now
        ;; repeat with a larger set of known safe
        (get-varcalls-loop names vc-now))))

(define (get-varcalls names)
  (get-varcalls-loop names *export-varcalls*))


;; Get $(call ...) argument list with N parameters: $1,$2,$3,...
(define (narglist nargs ?list)
  (subst " " "" (addprefix ",$" (if (filter-out 0 nargs) (urange 1 nargs)))))

(expect "" (narglist 0))
(expect ",$1,$2,$3" (narglist 3))


;; Replace $(call NAME,$1,$2,$3,...,$N) with $(NAME) if {NAME: N}
;; appears in varfuncs.
;;
(define (opt-varcalls code varfuncs)
  (define `{=name: nargs} varfuncs)

  (define `opt-code
    (subst (.. "$(call " name (narglist nargs) ")")
           (.. "$(" name ")")
           code))

  (if varfuncs
      (opt-varcalls opt-code (rest varfuncs))
      code))

(expect "x = $(foo)$(bar)"
        (opt-varcalls "x = $(call foo)$(call bar,$1,$2,$3)"
                      {foo: 0, bar: 3}))


;;----------------------------------------------------------------
;; Scam-to-Minion/Make conversion
;;----------------------------------------------------------------

(define (minionize code)
  (subst "$  " "$(\\s)"     ;; SCAM runtime -> Minionese
         "$ \t" "$(\\t)"    ;; SCAM runtime -> Minionese
         "$ " ""            ;; not needed to avoid keywords in "=" defns
         "$(if ,,,)" "$;"   ;; SCAM runtime -> Minionese
         "$(if ,,:,)" ":$;" ;; SCAM runtime -> Minionese
         "$(&)" "$&"        ;; smaller, isn't it?
         "$`" "$$"          ;; SCAM runtime -> Minionese
         code))


(define (rfv-loop code new-names)
  (define `old (subst " " "" (patsubst "%" ";" new-names)))
  (define `new (word 1 new-names))
  (define `(var-ref name)
    (if (filter "; w x y" name)
        (.. "$" name)
        (.. "$(" name ")")))

  (define `next-code
    (subst (.. "$(foreach " old ",") (.. "$(foreach " new ",")
           (var-ref old) (var-ref new)
           code))

  (if new-names
      (rfv-loop next-code (rest new-names))
      code))

;; We need to rename SCAM's automatic variables (;, ;;, ...)  because SCAM
;; uses $; for ",".  Also, the user may request renaming with some specific
;; variables via export-modify-foreach.
;;
;; Note: these transformation must occur before Minionization ($$ will not
;; appear).
;;
(define (rename-foreach-vars code ?names)
  (rfv-loop code (reverse (._. names "w x y"))))


(expect "$(foreach w,a b c,$(foreach x,1 2 3,$w,$x))"
        (rename-foreach-vars
         "$(foreach ;,a b c,$(foreach ;;,1 2 3,$;,$(;;)))"))

(expect "$(foreach foo,,$(foreach bar,,$(foreach w,,$(foo)$(bar)$w)))"
        (rename-foreach-vars
         "$(foreach ;,,$(foreach ;;,,$(foreach ;;;,,$;$(;;)$(;;;))))"
         "foo bar"))


;; Replace SCAM automatic variables with those listed in NAMES
;;
(define (export-modify-foreach func names)
  &public
  (set-native-fn func (rename-foreach-vars (native-value func) names)))


(define (assignment name code)
  (.. name " = " (subst "\n" "$(\\n)"
                        "#" "\\#"
                        code)))


(define (extract-exports)
  &public

  ;; collect functions to be exported from the current environment
  (define `exported-funcs
    (sort
     (foreach (v (filter-out *export-excludes*
                             (filter export-patterns
                                     (native-value ".VARIABLES"))))
       (if (filter "f%" (native-origin v))
           v))))

  ;; generate body of Make code that defines these functions
  (define `scam-defns
    (foreach (name exported-funcs "\n")
      (assignment name (native-value name))))

  ;; identify varcall optimization candidates
  (define `varsafe-funcs
    (get-varcalls exported-funcs))

  ;; optimize and convert to Make/Minion-compatible format
  (define `body
    (minionize
     (rename-foreach-vars
      (opt-varcalls scam-defns varsafe-funcs))))

  body)
