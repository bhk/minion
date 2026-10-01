;; Rule generation and caching

(require "base.scm")
(require "objects.scm")
(require "tools.scm")


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
  &public
  &native
  (define `escaped
    (subst "\\" "\\\\"
           "\t" "\\t"
           "\n" "\\n"
           value))
  (.. "printf \"%b\" " (_shellQuote escaped)))


;;----------------------------------------------------------------
;; rollups: Traverse instances and their {needs} transitively.
;;
;; This is done in the following cases:
;;
;;   E: Eval'ed rules: We find IDs for rules that need to be generated prior
;;      to Make's rule processing phase, descending from a set of rules
;;      identified by the command-line goals.
;;
;;   C: Cached rules: We find IDs for rules that need to be written to the
;;      cache file.
;;
;;   H: Help: Some messages list direct & indirect dependencies.
;;
;; Case H is simple, because caching is not in effect when `help` targets
;; are processed; rollups = transitive closure of {needs}.  Cases E & C
;; would be simple if we were only caching rules, but we also cache
;; *rollups* to avoid the cost of rollups when a cache is present ... it can
;; take 5s in a 30,000-rule project without a cache versus milliseconds with
;; one.  (The time spent is not algorithm-sensitive; just evaulating {needs}
;; once for each instance takes the bulk of the time.)
;;
;; Our approach is to define a "needs var" in the cache file for each cached
;; ID that lists the *un-cached* rollups for that ID. This requires that we
;; do the following:
;;
;;   C: Generate transitive dependencies *per-instance*.  To do this
;;      without terrible performance, _rollup uses memoization.
;;
;;   E: Instead of getting all rollups for goals and then filtering out the
;;      cached IDs, we use a pruning (or skipping) traversal, _rollupEx.
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
