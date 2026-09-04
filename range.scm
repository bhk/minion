(require "core")
(require "export.scm")

(define `digits "0 1 2 3 4 5 6 7 8 9")

;; Return a range of sequential integers, with leading zeros, with
;; elements from 0 through at least MAX-1.
;;
;;    e.g.:  "0 1 2 ... 8 9"  or  "000 001 002 ... 998 999"
;;
(define (_rxn numbers max)
  &native
  (define `x10
    (foreach (d digits)
      (addprefix d numbers)))

  (if (word max numbers)
      ;; handle boundary case where numbers has MAX words and last is MAX-1.
      numbers
      (_rxn x10 max)))


;; Return a list of integers in the range MIN..MAX (inclusive).
;;
;; MIN is a positive integer.
;; MAX is a non-negative integer.
;;
;; MIN and MAX must be in "plain" decimal format (no scientific notation or
;; decimals).
;;
;; Memory requirements and execution time are proportional to MAX, not
;; (MAX - MIN).
;;
(define (_range min max)
  &native
  &public
  (define `(trimLeadingZeros list)
    (subst " 0000" " "
           " 00" " "
           " 0" " "
           (.. " " list " " max)))

  (if (subst 0 "" max)
      (wordlist min max (trimLeadingZeros (_rxn digits max)))))


(expect "" (_range 1 0))
(expect "1" (_range 1 1))
(expect "8 9 10 11 12" (_range 8 12))

(show-export "_rxn")
(show-export "_range")
