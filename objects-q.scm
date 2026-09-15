;; Tests for objects.scm

(require "core")
(require "base.scm")
(require "export.scm")

(require "objects.scm" &private)

;;--------------------------------
;; Tests
;;--------------------------------

(let-global ((_E0 "-"))
  (expect (idClass "f") "_File")
  (expect (idClass "C(a)") "C")
  (expect (idClass "(a)") "-")
  (expect (idClass "C(a") "-")
  (expect (idClass "Ca)") "-")
  (expect (idClass "Ca)b") "-")
  (expect (idClass "C(a)b") "-"))

;;
;; Test class hierarchy
;;

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
(set-native-fn "C.idp" "{B(other).self}")

(set-native    "C(a).s" "C(a).s:$0 $$ {x}")        ;; simple instance prop
(set-native-fn "C(a).r" "C(a).r:$0 $$ {class}")    ;; recursive instance prop
(set-native-fn "C(a).ia" "C(a).ia + {inherit}")    ;; recursive w/ {inherit}
(set-native-fn "C(a).icm" "C(a).icm + {inherit}")  ;; recursive w/ {inherit}


;; _chain, chp+, _walk

(expect (_chp+ "C") "Mixin B")
(expect (_chp+ "Mixin B") "B")
(expect (_walk "z" "C") "C")
(expect (_walk "m" "C") "Mixin B")


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

;; {ID.PROP} functionality
(expect (get "idp" "C(a)") "B(other)")


;; _File(PLAIN) defaulting ... note _self does *not* reflect _File(xxx), but
;; that only affects the _File class itself.  $(_argText) seems to reflect
;; PLAIN.
(set-native-fn "_File.id" "$(_class)($(_argText))")
(expect (get "id" "f") "_File(f)")
(export-exclude "_File.id")

;; _E0 errors

(expectInError (get "p" "(a)") "Mal-formed instance name '(a)'\nNo CLASS")
(expectInError (get "p" "C(a") "No ')' at end")
(expectInError (get "p" "C(a)b") "No ')' at end")
(expectInError (get "p" "Ca)") "Unbalanced ')'")

;; _E1 errors

;; _e1-msg caller/site descriptions
(let-global ((_self "C(a)")
             (_class "C"))
  ;; site
  (expect 1 (see (.. "minion: Undefined property {icm}\n"
                     "on instance: C(a)\n"
                     "via {inherit} in:\n\n"
                     "   C.icm = C.icm + {inherit}\n\n")
                 (e1-msg "icm" nil "C.icm")))
  ;; caller is &C.P memo of C.P
  (expect 1 (see "during call to:\n\n   C.z =" (e1-msg "p" "&C.z" nil)))
  ;; caller is &C.P memo of inherited prop
  (expect 1 (see "B.y =" (e1-msg "p" "&C.y" nil)))
  ;; caller is complex &CHP.P
  (expect 1 (see "Mixin.m =" (e1-msg "p" "&Mixin B.m" nil)))
  ;; caller is &I.P
  (expect 1 (see "C(a).r =" (e1-msg "p" "C(a).r" nil)))
  ;; caller is OTHER
  (expect 1 (see "during call to:\n\n   _shell =" (e1-msg "p" "_shell" nil)))
  ;; bad class?
  (let-global ((_class "CX"))
    (expect 1 (see "CX.inherit is not defined" (e1-msg "p" "foo" nil)))))

(expectInError (get "u" "C(a)") "Undefined property {u}\non instance: C(a)")

(set-native-fn "C.e1" "{inherit}")
(expectInError (get "e1" "C(a)")
              (.. "minion: Undefined property {e1}\n"
                  "on instance: C(a)\n"
                  "via {inherit} in:\n\n   C.e1 = {inherit}"))

(set-native-fn "C(a).e2" "{inherit UNK}")
(expectInError (get "e2" "C(a)") "via {inherit UNK}")

(set-native-fn "C.eu" "{undef}")
(expectInError (get "eu" "C(a)") "during call to:\n\n   C.eu =")

;; _badAuto

(set-native-fn "BA" "$(call _badAuto,@,$0)")
(set-native-fn "C(a).w0" "$(BA)")
(set-native-fn "C.w1" "$(BA)")
(set-native-fn "C.w2" "$(call BA)")

(expectInError (get "w0" "C(a)")
               (.. "$$@ was evaluated prior to rule processing\nduring "
                   "evaluation of C(a).w0 in context of C(a)"))

(expectInError (get "w1" "C(a)")
               "evaluation of C.w1 in context of C(a)")

(expectInError (get "w2" "C(a)")
               "evaluation of $(call BA,...) in context of C(a)")
