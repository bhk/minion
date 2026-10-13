;;----------------------------------------------------------------
;; Functions used by built-in and/or user classes
;;----------------------------------------------------------------

(require "core")
(require "base.scm")
(require "objects.scm")


;; _wildcard, _shell, _var

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


;; Same as $(shell ...), but logs commands issues.
;;
(define (_shell command)
  &public
  &native
  (_set (native-name shellLog) (sort (._. shellLog (demote command))))
  (shell command))


(define (_var name)
  &public
  &native
  (_set (native-name varLog) (sort (._. varLog name)))
  (native-var name))


;; Generate a relative path from FROM to TO
;;
;; FROM may not contain `..` path elements.
;;
(define (_relpath from to)
  &native
  (if (filter "/%" to)
      to
      (if (filter ".." (subst "/" " " from))
          (error (.. "_relpath: '..' in " from))
          (or (foreach (f1 (filter "%/%" (word 1 (subst "/" "/% " from))))
                (_relpath (patsubst f1 "%" from)
                          (if (filter f1 to)
                              (patsubst f1 "%" to)
                              (.. "../" to))))
              to))))


;; Quote ARG for inclusion on the BASH command line
;;
(define (_shellQuote arg)
  &native
  (.. "'" (subst "'" "'\\''" arg) "'"))


;; Return a shell command that will write VALUE to stdout using /bin/printf
;;
(define (_printfCmd value)
  &public
  &native
  (define `escaped
    (subst "\\" "\\\\"
           "\t" "\\t"
           "\n" "\\n"
           value))
  (.. "printf \"%b\" " (_shellQuote escaped)))


;; _unique: Return unique entries in LIST without sorting


(define (_uniq2 list)
  &native
  (if list
      (._. (word 1 list) " " (_uniq2 (filter-out (word 1 list) list)))))

(define (_unique list)
  &native
  (define `(pquote value)
    (subst "^" "^c"
           "%" "^p" value))

  (define `(punquote value)
    (subst "^p" "%"
           "^c" "^" value))

  (strip (punquote (_uniq2 (pquote list)))))


;; Encode DATA to be shell-safe (within single quotes) and Make-safe (within
;; double-quotes or RHS of assignment) and to work with /bin/echo and
;; various shell echo builtins without further escaping.
;;
;; SUBSTR, if given, is substituted with a short unique substring, which
;; can reduce the size of the resulting string.
;;
(define (_vvEnc data substr)
  &native
  (define `enc
    (subst "!" "!1"
           "\\" "!B"
           substr "!@"
           "#" "!H"
           "\t" "!+"
           "\n" "!n"
           "$" "!S"
           "`" "!b"
           "\"" "!`"
           "'" "`"
           data))
  (.. "." enc "."))


;; Encode CODE for inclusion in a recipe so that it will be expanded again
;; if and only if the recipe is executed.  This bypasses the escaping
;; performed by _recipe, which ordinarily prevents expansion.  It might be
;; valuable when the rule involves a very expensive Make computation.
;; For example, consider these possible {command} values:
;;
;; @echo '$(call fn,X)'                -> OK
;; @echo '$$(call fn,X)'               -> displays "$$(call fn,FOO)"
;; @echo '$(call _lazy,$$(call fn,X))' -> OK, computed later
;;
(define (_lazy code)
  &native
  (subst "$" "\x1B" code))


;; Encode CONST to survive a second round of expansion in any Make
;; expression context.  This is useful with _lazy to include values computed
;; during property evaluation, because object properties are not available
;; during the rule processing phase.  Some example {command} values:
;;
;; A: @echo '$(call fn,{x})'                                -> OK
;; B: @echo '$(call _lazy,$$(call fn,{x}))'                 -> INCORRECT
;; C: @echo '$(call _lazy,$$(call fn,$(call _escape,{x}))'  -> OK
;;
;; In case C, `{}` is evaluated during property evaluation, but `fn` is
;; invoked when and if the recipe is executed.  The resulting value should
;; be the same as case A.
;;
;; In case B, {} will be evaluated during property evaluation and included
;; as part of the lazy expression, but if its value contains `$ or `,`
;; characters or unbalanced parentheses, the expansion of `$(call fn,...)`
;; during the rule processing phase will be inconsistent.
;;
(define (_escape const)
  &native
  (subst "$" "$$"
         ")" "$]"
         "(" "$["
         "," "$;"
         const))

(set-native ";" ",")

;; Escape a recipe to avoid another round of expansion during the rule
;; phase.
;;
(define `(_escapeR str)
  &public
  (subst "$" "$$"
         "\x1B" "$"
         str))


;; Encode COMMANDS for inclusion in a Make rule.  Tabs are inserted at the
;; start of each line, and "$" characters are protected to prevent further
;; expansion by Make in the rule processing phase.  (In the rare cases where
;; that is intended, use _lazy.)
;;
(define (_recipe commands)
  &native
  (_escapeR
   ;; indent lines and remove empty lines
   (subst "\t\n" ""
          (.. (subst "\n" "\n\t" (.. "\t" commands)) "\n"))))


;; Infer intermediate instances given a set of input IDs and a MAP
;; containing pairs `CLASSNAME.SUFFIX`.
;;
(define (_inferIDs ids map)
  &native

  (define `inferred
    (foreach (id ids)
      (define `out
        (if (filter "%)" id)
            (get "out" id)
            id))

      (or (filter "%)" (patsubst (.. "%" (or (suffix out) "."))
                                 (.. "%(" id ")")
                                 (._. map)))
          id)))

  (if map
      inferred
      ids))


;;----------------------------------------------------------------
;; _graphDeps, _graph, _traverse
;;----------------------------------------------------------------

(define `D "`")
(define `DD (.. D D))
(define `D_ (.. D " "))
(define `D__ (.. D "  "))

;; Remove empty slots from the *end* of SLOTS
;;
;; Example:
;;    + " 9"                !a! ! ! !b! ! 9
;;    patsubst "!" "! "     !a! !  !  !b! !  !  9
;;    subst "!  " "!!"      !a! !!!!!b! !!!!9
;;    filter                !a! !!!!!b!
;;    subst "!!" "! "       !a! ! ! !b!
;;
(define `(trim-empties slots)
  ;; make empty slots easy to identify
  (define `a (patsubst D D_ (._. slots 9)))
  ;; collapse empty slots with next slot
  (define `b (subst D__ DD a))
  ;; remove terminal "slot"
  (define `c (filter-out "%9" b))
  (subst DD D_ c))


;; Return textual representation of all dependencies among NODES
;;
;; (CH-FN CXT node) -> children of node
;; (NAME-FN CXT node) -> text to be displayed for node
;; NODES = nodes remaining to be drawn (two lines of text per node).
;;         This must be partially ordered (parents precede children).
;; SLOTS = columns representing parents.
;; OUT = previously rendered lines of text
;;
;; The algorithm does the following for each nod in NODES:
;;   concatenate "sticks" and "arrows" + NODE to OUT
;;   update SLOTS:
;;     remove NODE from every slot's list of pending children
;;     delete trailing empty slots
;;   update NODE to (rest NODES)
;;
(define (_graph ch-fn name-fn cxt nodes ?slots ?out)
  &native
  &public
  (define `node (word 1 nodes))
  (define `children (native-call ch-fn cxt node))
  (define `name (native-call name-fn cxt node))

  (define `(stick slot)
    (.. (if (filter D slot) " " "|") "  "))

  (define `(arrow slot node)
    (if (findstring (.. D node D) slot)
        "+->"
        (stick slot)))

  ;; Add new slot containing children of NODE, and remove NODE
  ;; from other slots.
  (define `newSlots
    (trim-empties
     (._. (subst (.. D node D) D slots)
          ;; convert list of children to slot format
          (.. D (subst " " "" (addsuffix D children))))))

  (define `newOut
    (.. out
        (foreach (slot slots)
          (stick slot))
        "\n"
        (foreach (slot slots)
          (arrow slot node))
        (if slots " ")
        name "\n"))

  (if nodes
      ;; Output lines for this node.
      (_graph ch-fn name-fn cxt (rest nodes) newSlots newOut)
      out))


;; Return list of descendants of NODES, ordered such that all parents
;; precede their children.
;;
;; CF = name of function to get children of a node
;; CC = context to pass to CF
;;
(define (_traverse cf cc nodes ?seen)
  &native
  (define `parent (word 1 nodes))
  (define `children (native-call cf cc parent))
  (define `next-seen (._. (filter-out parent seen) parent))

  (if parent
      (_traverse cf cc (._. children (rest nodes)) next-seen)
      seen))


;; Combine _graph and _traverse

(define (_graphDeps cf name-fn cxt nodes)
  &native
  &public
  (_graph cf name-fn cxt (_traverse cf cxt nodes)))


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
;;    "C(a).p"   -->  "_HelpGoal(C(a).p)"
;;    "@X"       -->  "_BuildGoal(@X)"
;;    "foo"      -->  ""           (presumably a matching Make rule exists)
;;
(define (_buildGoalID name)
  &native
  (if (or (_isInstance name)
          (_isIndirect name))
      (.. "_BuildGoal(" name ")")
      (if (isProperty name)
          (.. "_HelpGoal(" name ")")
          (_isAlias name))))
