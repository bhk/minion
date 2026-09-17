;;----------------------------------------------------------------
;; Functions used by built-in and/or user classes
;;----------------------------------------------------------------

(require "core")
(require "base.scm")
(require "objects.scm")


;;----------------------------------------------------------------
;; Shell- and command-related tools
;;----------------------------------------------------------------

;; Quote ARG for inclusion on the BASH command line
;;
(define (_shellQuote arg)
  &native
  (.. "'" (subst "'" "'\\''" arg) "'"))


;; Return a shell command that will write VALUE to stdout using /bin/printf
;;
(define (_printfCmd value)
  &native
  (define `escaped
    (subst "\\" "\\\\"
           "\t" "\\t"
           "\n" "\\n"
           value))
  (.. "printf \"%b\" " (_shellQuote escaped)))


;; Generate a relative path from FROM to TO
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


;;
;; _unique: Return unique entries in LIST without sorting
;;

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


;;----------------------------------------------------------------
;; Rule-generation
;;----------------------------------------------------------------


;; Return the variable portion of indirection ID.  Return nil if the ID ends
;; in @.
;;
;;    @VAR, C@VAR, D@C@VAR  -->  VAR, VAR, VAR
;;
(define (_ivar id)
  &native
  &public
  (filter-out "%@" (subst "@" "@ " id)))


(define (_EI id where)
  &native

  (_error
   (..
    "minion: Invalid target: '" id "'\n"
    (if (filter "%@" id)
        (.. "Name ends in '@'")
        (.. "References undefined variable '" (_ivar id) "'"))
    (if where
        (.. "\nFound while expanding "
            (if (filter "_BuildGoal(%" where)
                "command line goal"
                where)))
    "\n\n")))


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


;; Expand indirections in LIST, and translate bare alias names to instances.
;;
;; PROP is used in reporting "Found while expanding C(A).PROP" errors
;;
(define (_expand list ?prop)
  &native
  &public
  (_expandX list (.. _self "." prop)))


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
;; rollups: Traverse instances and their {needs} transitively.
;;
;; This is done in the following cases:
;;
;;   E: Rule eval: Finding IDs for rules that need to be generated prior to
;;      Make's rule processing phase.
;;
;;   C: Rule cache: Getting IDs for rules that need to be written
;;      to the cache file.
;;
;;   H: In help messages that list direct & indirect dependencies.
;;
;; Case H is simple: just transitively follow {needs}.  Cases E & C would be
;; simple if we were only caching rules, but we also cache *rollups* to
;; avoid the cost of rollups when a cache is present ... it can take 5s in a
;; 30,000-rule project without a cache versus milliseconds with one.  (The
;; time spent is not algorithm-sensitive; just evaulating {needs} once for
;; each instance takes the bulk of the time.)
;;
;; The approach is to define a "needs var" in the cache file for each cached
;; ID that lists the *un-cached* rollups for that ID. This requires the
;; following:
;;
;;   C: Generate transitive dependencies *per-instance*.  To do this
;;      without terrible performance, _rollup uses memoization.
;;
;;   E: Instead of getting all rollups for goals and then filtering out the
;;      cached IDs, we use a pruning (or skipping?) traversal, _rollupEx.
;;
;;----------------------------------------------------------------

;; Return transitive dependencies of ID, excluding non-instances.  Memoize
;; results so this can be applied efficiently to many IDs in arbitrary
;; order.
;;
(define (_rollupOne id)
  &native
  (define `memo-var (needs-memo-var id))
  (define `xdeps
    (sort (foreach (i (isInstance (get "needs" id)))
            (._. i (_rollupOne i)))))
  (or (native-value memo-var)
      (_set memo-var (or xdeps " "))))


;; Return IDS and their transitive dependencies, excluding non-instances.
;;
(define (_rollup ids)
  &native
  &public
  (sort
   (foreach (i (isInstance ids))
     (._. i (_rollupOne i)))))


;; Return IDS and their transitive dependencies that are instances,
;; excluding those listed in EXCLUDES.  For instances that are in EXCLUDES,
;; use $(rulecache-needs-var) rather than {needs} to obtain their
;; dependencies.
;;
(define (_rollupEx ids excludes ?seen)
  &native
  (define `deps
    (sort
     (._. (isInstance (get "needs" (filter-out excludes ids)))
          (foreach (i (filter excludes ids))
            (native-value (rulecache-needs-var i))))))

  (if ids
      (_rollupEx (filter-out (._. seen ids) deps)
                 excludes
                 (._. seen ids))
      (filter-out excludes seen)))


;;----------------------------------------------------------------
;; _group & _ungroup
;;----------------------------------------------------------------

(declare (_group list n) &native)
(declare (_ungroup grp) &native)

(begin
  (define `D "|")
  (define `DD (.. D D))
  (define `D0 (.. D 0))  ;; encodes " "
  (define `D1 (.. D 1))  ;; encodes D
  (define `D_ (.. D " "))

  ;; Group LIST into sub-lists of length N.
  ;;
  (define (_group list n)
    &native
    (define `dgroup (patsubst "%" D (wordlist 1 n list)))
    ;; MARKERS = for every word in LIST, D except DD at every Nth
    (define `markers (subst dgroup (.. dgroup D) (patsubst "%" D list)))

    (if list
        (subst DD ""    ;; don't collapse every Nth
               D_ D0    ;; collapse all other word boundaries
               (.. (join (subst D D1 list) markers) " "))))

  ;; Expand group(s) to an ordinary word list.
  ;;
  (define (_ungroup groups)
    &native
    (subst D0 " "
           D1 D
           groups)))


;;----------------------------------------------------------------
;; _graphDeps, _graph, _traverse
;;----------------------------------------------------------------

(declare (_graph fn-ch fn-names cxt nodes ?slots ?out) &native &public)

(begin
  ;; This delimiter must not appear anywhere in node names
  (define `D "`")
  (define `DD (.. D D))
  (define `D_ (.. D " "))
  (define `D__ (.. D "  "))

  (define `(stick slot)
    (.. (if (filter D slot) " " "|") "  "))

  (define `(arrow slot node)
    (if (findstring (.. D node D) slot)
        "+->"
        (stick slot)))

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

  (define `(tte in out)
    (expect (subst "!" D out) (trim-empties (subst "!" D in))))

  (tte "!a! ! ! !b! ! !c! ! !"
       "!a! ! ! !b! ! !c!")
  (tte "!a! ! ! !b! ! !c!"
       "!a! ! ! !b! ! !c!")
  (tte "! ! !" nil)


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
        out)))


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


;;----------------------------------------------------------------
;; Rule cache generation
;;----------------------------------------------------------------


;; Escape VALUE for inclusion literally in `ifeq "..." "..."` contexts.
(define (_qesc value)
  &native
  &public
  (subst "$" "$$"
         "\"" "$(\\q)"
         "#" "$(\\H)"
         "\n" "$(\n)"
         value))


(define (_checkValue cacheFile oldValue newExpr)
  &native
  (.. "\nifneq \"" (_qesc oldValue) "\" \"" newExpr "\"\n"
      "  $(info minion: $" newExpr " has changed!)\n"
      "  " cacheFile ": $(_forceTarget)\n"
      "endif\n"))


(define (_rcr2 cacheFile includedIDs excludedIDs groupSize)
  &native
  (define `cachedIDs
    (filter-out excludedIDs includedIDs))

  (define `tmpFile
    (.. cacheFile "_tmp_"))

  (define `(groupRules group)
    (foreach (i (_ungroup group))
      (.. "\n" (get "rule" i)
          (if excludedIDs
              (.. "\n" (rulecache-needs-var i) " = "
                  (filter excludedIDs (_rollupOne i))))
          "\n")))

  ;; Output validity checks for changes to _wildcard, _shell, or _var
  ;; results, and check `minionCache` and `minionNoCache` just in case
  ;; they were supplied via the environment.
  (define `epilogue-1
    (.. "_cachedIDs = " cachedIDs "\n"
        (foreach (v (._. "minionCache" "minionNoCache" varLog))
          (_checkValue cacheFile (native-var v) (.. "$(" v ")")))
        (if globLog
            (_checkValue cacheFile (wildcard globLog) (.. "$(wildcard " globLog ")")))
        (foreach (cmd shellLog)
          (_checkValue cacheFile (shell (promote cmd)) (.. "$(shell " (promote cmd) ")")))))

  (define `epilogue
    (subst "\n \n" "\n\n" "endif\n\nif" "else if" epilogue-1))

  (.. "@mkdir -p " (dir cacheFile) "\n"
      "@> " tmpFile "\n"  ;; create/clear file
      (foreach (g (_group cachedIDs groupSize))
        (.. "@" (_printfCmd (groupRules g)) " >> " tmpFile "\n"))
      ;; validity checks must be done *after* rules have been generated
      "@" (_printfCmd epilogue) " >> " tmpFile "\n"
      "@mv " tmpFile " " cacheFile "\n"))


;; Get target IDs referenced by a variable, and warn if any of them are
;; non-Minion ("plain" names that might be source files or make targets).
;;
(define (_varToIDs varName)
  &native
  (foreach (t (_expand (native-var varName)))
    (if (filter "%)" t)
        t
        (error (.. varName " references unknown target '" t "'")))))


;; Return the Make recipe (sequence of command lines) that will
;; generate a rule cache file.
;;
;; This consists largely of `printf` commands.  Each printf handles a
;; "group" of rules, because writing all rles in a single printf could
;; command exceed line length limits, while OTOH exec'ing one printf command
;; per rule would be slow.
;;
(define (_rulecacheRecipe cacheFile)
  &native
  &public

  (declare _cacheGroupSize &native)
  (define `includes (_rollup (_varToIDs "minionCache")))
  (define `excludes (filter "%)" (_varToIDs "minionNoCache")))

  (print "minion: Updating rule cache...")
  (_rcr2 cacheFile includes excludes _cacheGroupSize))


;; Evaluate rules of IDs and their transitive dependencies.
;;
(define (_evalRules ids excludes)
  &native
  (foreach (id (_rollupEx (sort (_isInstance ids)) excludes))
    (_eval (get "rule" id) id)))
