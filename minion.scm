;;----------------------------------------------------------------
;; minion.scm: Generate makefile definitions from SCAM definitions
;;----------------------------------------------------------------

(require "io")
(require "export.scm")

(require "base.scm")
(require "diag.scm")
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
  (define `output (.. (extract-exports) "\n" tail))

  (if o
      (write-file o output)
      (print output)))
