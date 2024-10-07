;;----------------------------------------------------------------
;; prototype.scm:  SCAM prototypes of functions for Minion
;;----------------------------------------------------------------

(require "io")
(require "export.scm")

(require "base.scm")
(require "objects.scm")
(require "tools.scm")
(require "outputs.scm")

(define `tail "
ifndef minionStart
  $(eval $(value _epilogue))
else
  minionEnd = $(eval $(value _epilogue))
endif
")

(define (main argv)
  (define `o (first argv))
  (define `output (.. (get-exports) "\n" tail))
  (if o
      (write-file o output)
      (print output)))
