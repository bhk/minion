(require "core")
(require "base.scm")
(require "objects.scm")
(require "tools.scm")
(require "help.scm" &private)


;; idc

(expect "Cls" (idc "Cls(arg)"))
(expect "Cls" (idc "Cls()"))
(expect nil (idc "(arg)"))
(expect nil (idc "arg)"))
(expect nil (idc "(arg"))
(expect nil (idc "arg"))


(define `(assignVars hash)
  (foreach (pair hash)
    (set-native-fn (dict-key pair) (dict-value pair))))

(assignVars
 { A.inherit: nil,
   A.prop: "aprop",
   B.inherit: "A",
   M.prop: "mprop + {inherit}",
   M.m: "MIXIN",
   C.inherit: "M B",
   C.prop: "cprop + {inherit}",
   (or "B(foo).px"): "PX + {inherit}",
   (or "B(foo).prop"): "FOO + {inherit}",
   (or "C(foo).ix"): "IX",
   (or "C(foo).prop"): "PROP + {inherit}" })


;; _describeProp

(expect (_describeProp "C(foo)" "prop")
        (.. "   C(foo).prop = PROP + {inherit}\n"
            "\n"
            "...wherein {inherit} references:\n"
            "\n"
            "   C.prop = cprop + {inherit}\n"
            "\n"
            "...wherein {inherit} references:\n"
            "\n"
            "   M.prop = mprop + {inherit}\n"
            "\n"
            "...wherein {inherit} references:\n"
            "\n"
            "   A.prop = aprop\n"))

(expect (_describeProp "UNDEF(a)" "foo")
        "   <missing definition!>\n")

;; _chain

(expect (_chain "C(foo)") "C(foo) C M B A")

;; _hasProperty

(expect (_hasProperty "m" "C(a)") 1)
(expect (_hasProperty "ix" "C(foo)") 1)
(expect (_hasProperty "un" "C(a)") nil)


;; _helpOnProperty

;; bypass the `print` within _helpOnProperty
(define (hop goal)
  (withInfoHook
   (let ((out (_helpOnProperty goal)))
     (.. *info* out))))


(expect (hop "B(foo).prop")
        (.. "B(foo) inherits from: B A\n"
            "\n"
            "{prop} is defined by:\n"
            "\n"
            "   B(foo).prop = FOO + {inherit}\n"
            "\n"
            "...wherein {inherit} references:\n"
            "\n"
            "   A.prop = aprop\n"
            "\n"
            "Its value is: 'FOO + aprop'\n"
            "\n"))


(expect 1 (see "Undefined property"
               (catchErrorIn (get "px" "B(foo)"))))

(expect 1 (see (.. "B(foo) inherits from: B A\n"
                   "\n"
                   "{px} is defined by:\n"
                   "\n"
                   "   B(foo).px = PX + {inherit}\n"
                   "\n"
                   "...wherein {inherit} references:\n"
                   "\n"
                   "   <missing definition!>\n"
                   "\n"
                   "Its evaluation results in an error:\n"
                   "minion: Undefined property {px}")
               (hop "B(foo).px")))
