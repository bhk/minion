;;----------------------------------------------------------------
;; Minion "Tools" functions
;;----------------------------------------------------------------

(require "core")
(require "export.scm")
(require "base.scm")
(require "objects.scm")

(export-text "# tools.scm")

;;----------------------------------------------------------------
;; _inferPairs
;;----------------------------------------------------------------


(define `(pair id file)
  (.. id "$" file))

(define (_pairIDs pairs)
  &native
  (filter-out "$%" (subst "$" " $" pairs)))

(export (native-name _pairIDs) 1)


(define (_pairFiles pairs)
  &native
  (filter-out "%$" (subst "$" "$ " pairs)))

(export (native-name _pairFiles) 1)

(expect "a.c" (_pairIDs "a.c"))
(expect "C(a.c)" (_pairIDs "C(a.c)$a.o"))

(expect "a.c" (_pairFiles "a.c"))
(expect "a.o" (_pairFiles "C(a.c)$a.o"))



;; Infer intermediate instances given a set of input IDs and their
;; corresponding output files.
;;
;; PAIRS = list of "ID$FILE" pairs, or just "FILE"
;;
(define (_inferPairs pairs inferClasses)
  &native
  (if inferClasses
      (foreach (p pairs)
        (define `id (_pairIDs p))
        (define `file (_pairFiles p))

        (define `inferred
          (word 1
                (filter "%)"
                        (patsubst (.. "%" (or (suffix file) "."))
                                  (.. "%(" id ")")
                                  inferClasses))))

        (or (foreach (i inferred)
              (pair i (get "out" i)))
            p))
      pairs))

(export (native-name _inferPairs) nil)


(set-native "IC(a.c).out" "out/a.o")
(set-native "IP(a.o).out" "out/P/a")
(set-native "IP(IC(a.c)).out" "out/IP_IC/a")

(expect (_inferPairs "a.x a.o IC(a.c)$out/a.o" "IP.o")
        "a.x IP(a.o)$out/P/a IP(IC(a.c))$out/IP_IC/a")


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


(begin
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
  nil)



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
;; Group LIST into sub-lists of length N.
;;----------------------------------------------------------------

;; Usage: (foreach (g (_group list)) ... (_ungroup g) ...)
;;
(declare (_group list n) &native)
(declare (_ungroup grp) &native)

(begin
  (define `D "|")
  (define `DD (.. D D))
  (define `D0 (.. D 0))  ;; encodes " "
  (define `D1 (.. D 1))  ;; encodes D
  (define `D_ (.. D " "))

  (define (_group list n)
    &native
    (define `dgroup (patsubst "%" D (wordlist 1 n list)))
    ;; MARKERS = for every word in LIST, D except DD at every Nth
    (define `markers (subst dgroup (.. dgroup D) (patsubst "%" D list)))

    (if list
        (subst DD ""    ;; don't collapse every Nth
               D_ D0    ;; collapse all other word boundaries
               (.. (join (subst D D1 list) markers) " "))))

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
;; Construct a graph of dependencies between instances.
;;----------------------------------------------------------------

(declare (_graph fn-prefix nodes ?slots ?out) &native)
(declare (_graph-trav get-children-fn nodes ?seen) &native)

(begin

  ;; This delimiter must not appear anywhere in node names
  (define `D "`")
  (define `DD (.. D D))
  (define `D_ (.. D " "))
  (define `D__ (.. D "  "))

  ;; 10K nodes should be more than enough
  (define `(rest lst) (wordlist 2 9999 lst))

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
  ;; FN-PREFIX us used to construct two function names
  ;;    FN-PREFIXchildren = function: node -> children
  ;;    FN-PREFIXname = function: node -> name
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
  (define (_graph fn-prefix nodes ?slots ?out)
    &native
    (define `(get-children node) (native-call (.. fn-prefix "children") node))
    (define `(get-name node) (native-call (.. fn-prefix "name") node))

    (define `node (word 1 nodes))

    ;; Add new slot containing children of NODE, and remove NODE
    ;; from other slots.
    (define `newSlots
      (trim-empties
       (._. (subst (.. D node D) D slots)
            ;; convert list of children to slot format
            (.. D (subst " " "" (addsuffix D (get-children node)))))))

    (define `newOut
      (.. out
          (foreach (slot slots)
            (stick slot))
          "\n"
          (foreach (slot slots)
            (arrow slot node))
          (if slots " ")
          (get-name node) "\n"))

    (if nodes
        ;; Output lines for this node.
        (_graph fn-prefix (rest nodes) newSlots newOut)
        out))


  ;; test _graph

  (define (sample-children node)
    &native
    (define `g
      { 0: [1 2 4],
        1: [3],
        2: [3],
        A: "D C B",
        B: "C E",
        C: "D",
        })

    (dict-get node g))

  (define (sample-name node)
    &native
    (if (filter 3 node)
        (.. "<" node ">")
        node))

  (expect
   (concat-vec [
                ""
                "0"
                "|  "
                "+-> 1"
                "|   |  "
                "+-> |   2"
                "|   |   |  "
                "|   +-> +-> <3>"
                "|  "
                "+-> 4"
                ""
                ]
               "\n")
   (_graph "sample-" "0 1 2 3 4" ""))


  ;; Return list of descendants of NODES, ordered such that all parents
  ;; precede their children.
  ;;
  (define (_graph-trav get-children-fn nodes ?seen)
    &native
    (define `parent
      (word 1 nodes))

    (if parent
        (_graph-trav get-children-fn
              (._. (native-call get-children-fn parent) (rest nodes))
              (._. (filter-out parent seen) parent))
        seen))


  (expect
   "A B C D E"
   (_graph-trav "sample-children" "A"))

  ;; Display a sample graph.
  ;; (print (_graph "sample-" (_graph-trav "sample-children" "A"))))

  nil)

(export (native-name _graph) nil)
(export (native-name _graph-trav) nil)
