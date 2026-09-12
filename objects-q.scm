;; Tests for objects.scm

(require "core")
(require "base.scm")
(require "export.scm")

(require "objects.scm" &private)

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
  (withErrorHook
   (expect expr value)
   (expect 1 (xsee error-content (first *error*)))))

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

(withErrorHook
 (expect nil (get "w0" "C(a)"))
 (expect 1 (xsee (.. "$$@ was evaluated prior to rule processing\nduring "
                     "evaluation of C(a).w0 in context of C(a)")
                 (first *error*))))
(withErrorHook
 (expect nil (get "w1" "C(a)"))
 (expect 1 (xsee (.. "evaluation of C.w1 in context of C(a)")
                 (first *error*))))

(withErrorHook
 (expect nil (get "w2" "C(a)"))
 (expect 1 (xsee "evaluation of $(call BA,...) in context of C(a)"
                 (first *error*))))
