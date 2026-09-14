(require "core")
(require "base.scm")
(require "compile.scm" &private)


(define (xsee a b)
  (or (see a b)
      (print "*** Did not see '" a "' in '" b "'")))

(set _cxInherit (lambda (p chp sv)
                  (.. "&" chp "Base." p)))

(define `(tcx src) (cxBody src "P" "CC" "CC.P"))

(define `(testNest text) (_cxNest (tokenize text)))
(expect nil (testNest "(a))"))
(expect nil (testNest "a(b))"))
(expect nil (testNest "((x)"))
(expect nil (testNest "a((x)"))
(expect "(a)(b)" (testNest "(a)(b)"))
(expect "a(b(,))$;" (testNest "a(b(,)),"))

;; level 1

(expect (tcx " $$ $x . () { } ${FOO$} ")" $$ $x . () { } {FOO} ")
(expect (tcx "{FOO}") "$(call .,FOO,$0)")
(expect (tcx " a {FOO} b ") " a $(call .,FOO,$0) b ")
(expect (tcx "{x} ${y$}") "$(call .,x,$0) {y}")
(expect (tcx "{}") "$(_self)")

;; level 2

(expect (tcx "{inherit}") "$(call &CCBase.P)")
(expect (tcx "{inherit X}") "$(call &CCBase.X)")

;; level 3

(expect (tcx "{$(var)}") "$(call .,$(var),$0)")
(expect (tcx "{$(x.y)}") "$(call .,$(x.y),$0)")
(expect (tcx "{{propName}}") "$(call .,$(call .,propName,$0),$0)")
(expect (tcx "{{{propName}}}") "$(call .,$(call .,$(call .,propName,$0),$0),$0)")

(expect (tcx "{Class(Arg).x}") "$(call get,x,Class(Arg))")
(expect (tcx "{{id}.{p}}") "$(call get,$(call .,p,$0),$(call .,id,$0))")
(expect (tcx "{$(var).$(pvar)}") "$(call get,$(pvar),$(var))")
(expect (tcx "{$(IVAR).$(PVAR)}") "$(call get,$(PVAR),$(IVAR))")
(expect (tcx "{$(id.name).$(p.name)}") "$(call get,$(p.name),$(id.name))")

(expect (tcx "{a,b}") "$(call .,a$;b,$0)")
(expect (tcx "{a b}") "$(call .,a b,$0)")

;; error detection

(define *ecx* nil)
(define `(tcxError body ?p)
  (let-global ((_cxbError (lambda (why what where prop)
                            (expect "P" prop)
                            (expect "CC.P" where)
                            (set *ecx* (.. why ":" (detokenize what)))))
               (*ecx* nil))
    (tcx body)
    *ecx*))

(expect "G1:{.}" (tcxError "a{.}z"))
(expect "G1:{..}" (tcxError "{x}{..}"))
(expect "G2:{a.b.c}" (tcxError "x{a.b.c}"))
(expect "UP:{a(b}" (tcxError "x{a(b}"))
(expect "UP:{a)b}" (tcxError "x{a)b}"))
(expect "IN:{inherit $(VAR)}" (tcxError "x{inherit $(VAR)}"))
(expect "UB:{z" (tcxError "a{z"))
(expect "UB:a}" (tcxError "a}z"))
