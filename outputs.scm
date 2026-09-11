(require "core")
(require "base.scm")

;;----------------------------------------------------------------
;; Output file defaults
;;----------------------------------------------------------------

;; The chief requirement for output file names is that conflicts must be
;; avoided.  Avoiding conflicts is complicated by the inference feature, which
;; creates multiple ways of expressing the same thing.  For example,
;; `LinkC(foo.c)` vs. `LinkC(CC(foo.c))` produce equivalent results,
;; but they are different instance names, and as such must have different
;; output file names.
;;
;; The strategy for avoiding conflicts begins with including all components
;; of the instance name in the default output path, as computed by
;; Builder.out.
;;
;; When there is a single argument value and it is also the first ID named
;; by {in}, we presume it is a valid path, and we incorporate it (or its
;; {out} property) into the output location as follows:
;;
;;     Encode ".."  and "."  path elements and leading "/" for safety and to
;;     avoid aliasing -- e.g., the instance names `C(f)` and `C(./f)` need
;;     different output files.  When {outExt} does not include `%`, we
;;     incorporate the input file extension into the output directory.
;;
;;     Instance Name          outDir                   outName
;;     --------------------   ----------------------   -------------
;;     CLASS(DIRS/NAME.EXT)   VOUTDIR/CLASS.EXT/DIRS/  NAME{outExt}
;;     CC(f.c)                .out/CC.c/               f.o
;;     CC(d/f.cpp)            .out/CC.cpp/d/           f.o
;;     CC(.././f.c)           .out/CC.c/_../_./        f.o
;;     CC(/d/f.c)             .out/CC.c/_root_/d/      f.o
;;
;;     Differentiate CLASS(FILE) from CLASS(ID) (where ID.out = FILE) by
;;     appending `_` to the class directory.  For readability, collapse
;;     "CLASS.EXT_/VOUTDIR/..." to "CLASS.EXT_...":
;;
;;     Instance Name          outDir                   outName
;;     ---------------------  ----------------------   -------
;;     LinkC(CC(f.c))         .out/LinkC.o_CC.c/       f
;;     LinkC(f.c)             .out/LinkC.c/            f       (*)
;;
;;     [*] Note on handling inference: We compute .outDir based on the named
;;         FILE (f.c) , not on the inferred `.out/CC.c/f.o`.
;;         Otherwise, the result would collide with LinkC(CC(f.c)).
;;
;; When the argument is an indirection, or is otherwise not a target ID used
;; in {in}, we use it as the basis for the file name.  Any "@" or "C@"
;; prefixes are merged into the class directory:
;;
;;     Instance Name          outDir                   outName
;;     --------------------   ----------------------   -----------
;;     LinkC(@VAR)            .out/LinkC_@/            VAR{outExt}
;;     LinkC(C2@VAR)          .out/LinkC_C2@/          VAR{outExt}
;;     Write(x/y/z)           .out/Write/x/y/          z{outExt}
;;
;; When the argument is complex (with named values or comma-delimited
;; values) we apply the above logic to the *first* value in the argument,
;; after including the entirety of the argument in the class directory,
;; with these transformations:
;;
;;   1. Encode unsafe characters
;;   2. Replace the first unnamed argument with a special character
;;      sequence.  This avoids excessively long directory names and reduces
;;      the number of directories needed for a large project.
;;
;;     Instance Name           outDir                          outName
;;     ---------------------   -----------------------------   ------------
;;     CLASS(D/NAME.EXT,...)   VOUTDIR/CLASS.EXT__{encArg}/D/  NAME{outExt}
;;     P(d/a.c,x.c,opt:=3)      .out/P.c__@1,x.c,opt@C3/d/      a
;;
;;
;; Output file names should avoid Make and shell special characters, so that
;; we do not need to quote them.  We rely on the restrictions of instance
;; syntax.  Here are the ASCII punctuation characters legal in Minion class
;; names, arguments, ordinary (source file) target IDs, and comma-delimited
;; argument values, alongside those unsafe in Bash and Make:
;;
;; File:   _ - + { } / ^ . ~
;; Class:  _ - + { } / ^   ~ !
;; Value:  _ - + { } / ^ . ~ ! @ : ( ) < >
;; Arg:    _ - + { } / ^ . ~ ! @ : ( ) < > ,
;; ~Make:                  ~     :     < >       [ ] * ? # $ % ; \ =
;; ~Bash:        { }       ~ !     ( ) < >   { } [ ] * ? # $ % ; \   | & ` ' "
;;


;; Encode all characters that may appear in class names or arguments with
;; fsenc characters.
;;
(define (_fsenc str)
  &native

  (subst "@" "@_"
         "|" "@1"
         "(" "@+"
         ")" "@-"
         "*" "@S"
         ":" "@C"
         "!" "@B"
         "~" "@T"
         "/" "@D"
         "<" "@l"
         ">" "@r"
         "{" "@L"
         "}" "@R"
         str))


;; Encode the directory portion of path with fsenc characters
;; Result begins and ends with "/".
;;
(define `(safe-path path)
  (subst "/" "//"
         "/_" "/__"
         "/./" "/_./"
         "/../" "/_../"
         "//" "/"
         "//" "/_root_/"
         (.. "/" path)))

(expect (safe-path "a.c") "/a.c")
(expect (safe-path "d/c/b/a") "/d/c/b/a")
(expect (safe-path "./../.d/_c/.a") "/_./_../.d/__c/.a")


;; Tail of _outBasis for an argument that is not being used as a target ID
;;
(define (_outBX arg)
  &native
  ;; E.g.: "/C@_ /D@_ /dir@Dvar"
  (define `a (addprefix "/" (subst "@_" "@_ " (_fsenc arg))))
  ;; E.g.: "_C@ _D@ /dir@Dvar"
  (define `b (patsubst "/%@_" "_%@" a))
  (subst " " "" "@D" "/" b))

(expect (_outBX "@var") "_@/var")
(expect (_outBX "@d/f") "_@/d/f")
(expect (_outBX "C@var") "_C@/var")
(expect (_outBX "abc") "/abc")

;; _outBasis for simple arguments
;;
;; arg = argument (a single value)
;; file = arg==in[1] ? (in[1].out || "-") : nil
;;    file => arg==in[1]
;;
(define (_outBS class arg outExt file)
  &native
  (define `.EXT
    (if (findstring "%" outExt) "" (suffix file)))

  (define `(collapse x)
    (patsubst (.. "_/" VOUTDIR "%") "_%" x))

  (.. (_fsenc class)
      .EXT
      (if file
          (collapse (.. (if (isInstance arg) "_")
                        (safe-path file)))
          (_outBX arg))))

;; arg = indirection (file must be nil because arg1 is not a target ID)
(expect (_outBS "C" "@var" nil nil) "C_@/var")
;; arg = file == in[1]
(expect (_outBS "C" "d/f.c" ".o" "d/f.c")  "C.c/d/f.c")
;; arg = ID == in[1]
(expect (_outBS "P" "C(d/f.c)" nil ".out/C/f.o")  "P.o_C/f.o")
;; arg != in[1]
(expect (_outBS "P" "C(d/f.c)" nil nil)  "P/C@+d/f.c@-")


;; _outBasis for complex arguments, or non-input argument
;;
(define `(_outBC class arg outExt file arg1)
  (_outBS (.. class
              (subst (.. "_" (or arg1 "|")) "_|" (.. "_" arg)))
          (or arg1 "out")
          outExt
          file))

;; Generate path to serve as basis for output file defaults
;;
;;  class = this instance's class
;;  arg = this instance's argument
;;  outExt = {outExt} property; if it contains "%" we assume the input file
;;           prefix will be preserved
;;  file = output of first target ID mentioned in {in}  *if* the ID == arg1
;;  arg1 = (word 1 (_getHash nil (_argHash arg)))
;;
;; We assume Builder.outBasis looks like this:
;;    $(call _outBasis,$C,$A,{outExt},FILE,$(_arg1))
;; where FILE = $(call get,out,$(filter $(_arg1),$(word 1,$(call _expand,{in}))))
;;
(define (_outBasis class arg outExt file arg1)
  &native
  (if (filter arg1 arg)
      (_outBS class arg outExt file)
      (_outBC class arg outExt file arg1)))


(begin
  ;; test _outBasis

  (define class-exts
    { C: ".o", P: "", PX: "" })

  (define test-files
    { "C(a.c)": ".out/C.c/a.o",
      "File(d/a.c)": "d/a.c",
      "C(d/a.c)": ".out/C.c/d/a.o",
      })

  (define (get-test-file class arg1)
    (cond ((filter "%X" class) nil)
          ((findstring "@" arg1) nil)    ;; indirections are not IDs
          ((filter "%)" arg1) (or (dict-get arg1 test-files)
                                  (error (.. "Unknown ID: " arg1))))
          (else arg1)))

  (define `(t1 id out)
    (define class (word 1 (subst "(" " " id)))
    (define arg (patsubst (.. class "(%)") "%" id))
    (define arg1 (word 1 (_hashGet (_argHash arg))))
    (define `outExt (dict-get class class-exts "%"))
    (define `file (get-test-file class arg1))

    (expect (_outBasis class arg outExt file arg1)
            out))

  ;; C(FILE) (used as an input ID)
  (t1 "C(a.c)"          "C.c/a.c")
  (t1 "C(d/a.c)"        "C.c/d/a.c")
  (t1 "D(d/a.c)"        "D/d/a.c")
  (t1 "C(/.././a)"      "C/_root_/_../_./a")
  (t1 "C@!(a.c)"        "C@_@B/a.c")

  ;; C(INSTANCE) (used as an input ID)
  (t1 "P(C(a.c))"       "P.o_C.c/a.o")
  (t1 "P(C(d/a.c))"     "P.o_C.c/d/a.o")
  (t1 "P(File(d/a.c))"  "P.c_/d/a.c") ;; .out = d/a.c

  ;; C(SIMPLE) (NOT an input ID)
  (t1 "X(C(A))"       "X/C@+A@-")

  ;; C(@VAR) (NOT an input ID)
  (t1 "C(@var)"         "C_@/var")

  ;; C(CLS@VAR) (NOT an input ID)
  (t1 "C(D@var)"        "C_D@/var")
  (t1 "C(D@E@var)"      "C_D@_E@/var")
  (t1 "C(D@E@d/var)"    "C_D@_E@/d/var")

  ;; Complex (arg1 is an input ID)
  (t1 "P(a,b)"          "P_@1,b/a")
  (t1 "P(d/a.c,o:3)"    "P_@1,o@C3.c/d/a.c")
  (t1 "Q(d/a.c,o:3)"    "Q_@1,o@C3/d/a.c")
  (t1 "P(C(d/a.c),o:3)" "P_@1,o@C3.o_C.c/d/a.o")
  (t1 "P(@v,o:3)"       "P_@1,o@C3_@/v")
  (t1 "P(C@v,o:3)"      "P_@1,o@C3_C@/v")

  ;; Complex (arg1 is NOT an input ID)
  (t1 "PX(C(a.c),b)"    "PX_@1,b/C@+a.c@-")
  (t1 "P(x:1,y:2)"      "P_x@C1,y@C2/out")  ;; no unnamed arg

  nil)
