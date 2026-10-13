(require "core")
(require "base.scm")
(require "objects.scm")


;;----------------------------------------------------------------
;; "Flat" target scheme
;;----------------------------------------------------------------
;;
;; First we compute `inName`, then apply the `outExt` transformation.
;;
;;    arg1               in {in}?   inName
;;    ----------------   --------   ----------------
;;    Class(@VAR)        yes        VAR
;;    Class(C2@VAR)      yes        C2-VAR
;;    Class(@*.c)        yes        _.c
;;    Class(C(...))      yes        (notdir {<})
;;    Class(OTHER)       yes        (notdir {<})
;;
;;    Class(C(...))      no         {C(...).out}
;;    Class(OTHER)       no         OTHER
;;    Class()            no         Class
;;
(define (_outName arg1 outExt)
  &native

  ;; Replace indirection characters that are not FS-safe
  (define `(wcClean str)
    (subst "~" "_"
           "*" "_"
           str))

  (define `inName
    (or (notdir
         (if (filter arg1 (. "in"))
             (if (_isIndirect arg1)
                 (wcClean (subst "@" "-" (patsubst "@%" "%" arg1)))
                 (. "<"))
             (if (isInstance arg1)
                 (get "out" arg1)
                 arg1)))
        _class))

  (foreach (name (word 1 inName))
    (.. (or (basename name)
            _class)
        (subst "%" (suffix name) outExt))))


;;----------------------------------------------------------------
;; "Tree" target scheme
;;----------------------------------------------------------------
;;
;; Tree paths include the class name and input path directories in the
;; target directory.
;;
;;    arg1               in {in}?   deepOutDir
;;    ----------------   --------   ----------------
;;    Class(C(...))      yes        VOUTDIR/Class/(dir {<})
;;    Class(PLAIN)       yes        VOUTDIR/Class/(dir {<})
;;    Class(C(...))      no         VOUTDIR/Class/(dir {arg1.out})
;;    all others         --         VOUTDIR/Class/
;;

;; Embed a relative path within `outdir`.
(define `(nest-path outdir path)
  (subst "/" "//"
         "/_" "/__"
         "/./" ""
         "/../" "/_../"
         "//" "/"
         "//" "/_root_/"
         (.. "/" outdir) "_"
         (.. outdir path)))


(define (_outDirTree arg1)
  &native

  (define `dir
    (.. _class "/"
        (dir
         (if (filter arg1 (. "in"))
             (if (_isIndirect arg1)
                 nil
                 (. "<"))
            (if (isInstance arg1)
                (get "out" arg1))))))

  (nest-path VOUTDIR dir))


;; Here are the ASCII punctuation characters legal in Minion class names,
;; arguments, ordinary (source file) target IDs, and instance argument names
;; and values, alongside those unsafe in Bash arguments and Make targets and
;; prerequisites.
;;
;; Class:  _ - +
;; Name:   _ - + . @ ,
;; Value:  _ - + . @ , / ~ : * ( )
;; ~Make:                ~ : *     < >     [ ]   ? # $ % ; \ =
;; ~Bash:                ~   * ( ) < > { } [ ] ! ? # $ % ; \   | & ` ' "
;;
;; FS:     _ - + . @
;;
;; Note that `=` could be used in a file name, but it requires escaping on
;; LHS of Make variable assignments, and cannot be included in a Make goal.


;; Make STR filesystem-safe by removing unsafe characters that are legal in
;; Minion instances.
;;
(define (_fsClean str)
  &native
  (subst ")" ""
         "(" "_"
         "," "-"
         "~" "-"
         ":" "-"
         "*" "-"
         "/" "-"
         str))
