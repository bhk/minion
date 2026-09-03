;;----------------------------------------------------------------
;; Minion "Tools" functions
;;----------------------------------------------------------------

(require "core")
(require "export.scm")
(require "base.scm")
(require "objects.scm")

(export-text "# tools.scm")


;;----------------------------------------------------------------
;; _inferIDs
;;----------------------------------------------------------------

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

(export (native-name _inferIDs) nil)

(set-native "IC(a.c).out" "out/a.o")
(set-native "IP(a.o).out" "out/P/a")
(set-native "IP(IC(a.c)).out" "out/IP_IC/a")


(expect (_inferIDs "a.x a.o IC(a.c)" "IP.o")
        "a.x IP(a.o) IP(IC(a.c))")

(expect (_inferIDs "y a.x a.o IC(a.c)" "IP.o")
        "y a.x IP(a.o) IP(IC(a.c))")


;;----------------------------------------------------------------
;; _depsOf, _rollup, _rollupEx
;;----------------------------------------------------------------

;; Return transitive dependencies of ID, excluding non-instances.  Memoize
;; results so this can be applied efficiently to many IDs in arbitrary
;; order.
;;
(define (_depsOf id)
  &native
  (define `memoVar (.. "_&deps-" id))
  (define `xdeps
    (sort (foreach (i (isInstance (get "needs" id)))
            (._. i (_depsOf i)))))
  (or (native-value memoVar)
      (_set memoVar (or xdeps " "))))

(export (native-name _depsOf) nil)


;; Return IDS and their transitive dependencies, excluding non-instances.
;;
(define (_rollup ids)
  &native
  (sort
   (foreach (i (isInstance ids))
     (._. i (_depsOf i)))))

(export (native-name _rollup) 1)


;; Return IDS and their transitive dependencies that are instances,
;; excluding those listed in EXCLUDES.  For instances that are in EXCLUDES,
;; use $($(_i_cachedNeeds)) rather than {needs} to obtain their
;; dependencies.
;;
(define (_rollupEx ids excludes ?seen)
  &native
  (define `(cachedNeeds id)
    (native-value (.. "_" id "_needs")))

  (define `deps
    (sort
     (._. (isInstance (get "needs" (filter-out excludes ids)))
          (foreach (i (filter excludes ids))
            (cachedNeeds i)))))

  (if ids
      (_rollupEx (filter-out (._. seen ids) deps)
                 excludes
                 (._. seen ids))
      (filter-out excludes seen)))

(export (native-name _rollupEx) nil)

;; Test _depsOf, _rollup, _rollupEx
(set-native "R(a).needs" "R(b) R(c) x y z")
(set-native "R(b).needs" "R(c) R(d) x y z")
(set-native "R(c).needs" "R(d)")
(set-native "R(d).needs" "R(e)")
(set-native "R(e).needs" "")

(expect (_depsOf "R(a)")
        "R(b) R(c) R(d) R(e)")

(expect (_rollup "R(a)")
        "R(a) R(b) R(c) R(d) R(e)")

(expect (strip (_rollupEx "R(a)" ""))
        "R(a) R(b) R(c) R(d) R(e)")

(expect (strip (_rollupEx "R(a)" "R(d)"))
        "R(a) R(b) R(c)")

(set-native "_R(d)_needs" "R(x)")
(set-native "R(x).needs" "")

(expect (strip (_rollupEx "R(a)" "R(d)"))
        "R(a) R(b) R(c) R(x)")


;;----------------------------------------------------------------
;; _relpath
;;----------------------------------------------------------------

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

(export (native-name _relpath) nil)

(expect (_relpath "a/b/c" "/x") "/x")
(expect (_relpath "a" "x/y") "x/y")
(expect (_relpath "a/b" "x/y") "../x/y")
(expect (_relpath "x/b" "x/y") "y")
(expect (_relpath "a/b/c"
                  "a/x/y") "../x/y")


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

(export (native-name _group) nil)
(export (native-name _ungroup) nil)

(expect (_group "a | c d e f g h" 3)
        "a|0|1|0c d|0e|0f g|0h|0")

(define `(group-test list n out)
  (expect (foreach (g (_group list n))
            (.. "<" (foreach (i (_ungroup g)) i) ">"))
          out))

(group-test "a b c"    1 "<a> <b> <c>")
(group-test ""         2 "")
(group-test "a"        2 "<a>")
(group-test "a b"      2 "<a b>")
(group-test "a b c"    2 "<a b> <c>")
(group-test "a b c d e f g h"  3 "<a b c> <d e f> <g h>")


;;----------------------------------------------------------------
;; _graphDeps, _graph, _traverse
;;----------------------------------------------------------------

(declare (_graph fn-ch fn-names cxt nodes ?slots ?out) &native)
(declare (_traverse children-fn children-cxt nodes ?seen) &native)
(declare (_graphDeps children-fn name-fn cxt nodes) &native)

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
        out))

  (define `test-graph
    { 0: [1 2 4],
      1: [3],
      2: [3],
      A: "D C B",
      B: "C E",
      C: "D",
      })

  (define (test-children G node)
    (dict-get node G))

  (define (test-name cxt node)
    (if (filter 3 node)
        (.. "<" node ">")
        node))

  (expect
   (concat-vec [""
                "0"
                "|  "
                "+-> 1"
                "|   |  "
                "+-> |   2"
                "|   |   |  "
                "|   +-> +-> <3>"
                "|  "
                "+-> 4"
                ""]
               "\n")
   (_graph (native-name test-children) (native-name test-name) test-graph
           "0 1 2 3 4"))


  ;; Return list of descendants of NODES, ordered such that all parents
  ;; precede their children.
  ;;
  ;; CF = name of function to get children of a node
  ;; CC = context to pass to CF
  ;;
  ;;     (native-call CF CC node) -> children of node
  ;;
  (define (_traverse cf cc nodes ?seen)
    &native
    (define `parent
      (word 1 nodes))

    (if parent
        (_traverse cf
                   cc
                   (._. (native-call cf cc parent) (rest nodes))
                   (._. (filter-out parent seen) parent))
        seen))

  (expect "A B C D E"
          (_traverse (native-name test-children) test-graph "A"))


  ;; Combine _graph and _traverse
  ;;
  (define (_graphDeps cf name-fn cxt nodes)
    &native
    (_graph cf name-fn cxt (_traverse cf cxt nodes)))

  ;; Display a sample graph.
  ;; (print (_graphDeps (native-name test-children) (native-name test-name) test-graph "A"))

  nil)

(export (native-name _graph) nil)
(export (native-name _traverse) nil)
(export (native-name _graphDeps) nil)

;;----------------------------------------------------------------
;; _uniq
;;----------------------------------------------------------------


(define `(pquote value)
  (subst "^" "^c"
         "%" "^p" value))

(define `(punquote value)
  (subst "^p" "%"
         "^c" "^" value))

(define (_uniqQ list)
  &native
  (if list
      (._. (word 1 list) " " (_uniqQ (filter-out (word 1 list) list)))))

;; Return unique entries in LIST without sorting
;;
(define (_unique list)
  &native
  (strip (punquote (_uniqQ (pquote list)))))

(export (native-name _uniqQ) nil)
(export (native-name _unique) nil)

(expect (_unique "a b a c a b c c") "a b c")
(expect (_unique "a b % ^ a b % ^") "a b % ^")


;;----------------------------------------------------------------
;; Rule cache generation
;;----------------------------------------------------------------

(declare (_isAlias name) &native &public)
(declare (_isInstance name) &native &public)
(declare (_isIndirect name) &native &public)

;; Generate a `printf` command line
(declare (_printf text) &native &public)


;; Translate a list of goals into IDs
(define (_goalsToIDs goals where)
  &native
  (_expand (foreach (g goals)
             (or (_isGoal g)
                 (error (.. where " contains unknown goal '" g "'"))))
           where))


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
              (.. "\n_" i "_needs = "
                  (filter excludedIDs (_depsOf i))))
          "\n")))

  ;; Output validity checks for changes to _wildcard, _shell, or _var
  ;; results, and check `minionCache` and `minionNoCache` just in case
  ;; they were supplied via the environment.
  (define `epilogue
    (.. "_cachedIDs = " cachedIDs "\n"
        (foreach (v (._. "minionCache" "minionNoCache" varLog))
          (_checkValue cacheFile (native-var v) (.. "$(" v ")")))
        (if globLog
            (_checkValue cacheFile (wildcard globLog) (.. "$(wildcard " globLog ")")))
        (foreach (cmd shellLog)
          (_checkValue cacheFile (shell (promote cmd)) (.. "$(shell " (promote cmd) ")")))))

  (.. "@mkdir -p " (dir cacheFile) "\n"
      "@> " tmpFile "\n"  ;; create/clear file
      (foreach (g (_group cachedIDs groupSize))
        (.. "@" (_printf (groupRules g)) " >> " tmpFile "\n"))
      ;; validity checks must be done *after* rules have been generated
      "@" (_printf epilogue) " >> " tmpFile "\n"
      "@mv " tmpFile " " cacheFile "\n"))


(define (_varToIDs varName)
  &native
  (_goalsToIDs (native-var varName) varName))


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

  (print "Updating Minion cache...")
  (_rcr2 cacheFile includes excludes _cacheGroupSize))


(export (native-name _goalsToIDs) 1)
(export (native-name _rulecacheRecipe) nil)
(export (native-name _rcr2) nil)
(export (native-name _varToIDs) 1)
(export (native-name _checkValue) 1)
(export (native-name _qesc) 1)
