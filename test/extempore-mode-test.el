;;; extempore-mode-test.el --- Tests for extempore-mode  -*- lexical-binding: t -*-

;;; Commentary:

;; emacs -Q --batch -L . -l test/extempore-mode-test.el -f ert-run-tests-batch-and-exit
;;
;; The tests which evaluate need an Extempore: EXTEMPORE_TEST_PROGRAM names an
;; extempore binary with `extempore lsp', and EXTEMPORE_TEST_PORT the port of a
;; running Extempore's nREPL server.  Without them they are skipped.

;;; Code:

(require 'ert)
(require 'extempore-mode)

(defvar extempore-test-program (getenv "EXTEMPORE_TEST_PROGRAM"))
(defvar extempore-test-port
  (and (getenv "EXTEMPORE_TEST_PORT") (string-to-number (getenv "EXTEMPORE_TEST_PORT"))))

(ert-deftest extempore-xtm-files-open-in-extempore-mode ()
  (should (eq (assoc-default "song.xtm" auto-mode-alist #'string-match) 'extempore-mode)))

(ert-deftest extempore-summary-of-a-result ()
  (should (equal (extempore--summary '(:values ["1" "2"] :out "")) "=> 1  => 2"))
  (should (equal (extempore--summary '(:values [] :out "hi\nthere\n")) "hi"))
  (should (equal (extempore--summary '(:values [] :out "")) "evaluated"))
  (should (equal (extempore--summary '(:values [] :out "" :interrupted t)) "interrupted"))
  (should (equal (extempore--summary '(:values [] :out "" :error (:message "bad\nworse")))
                 "bad")))

(defconst extempore-test-indented
  "(define (f x)
  (cond
    ((> x 0)
     (xtc:aot:suppress-aot-do
      (sys:load \"a.xtm\")))
    (else
     (begin (println x)
            x))))

(def-instrument beep
  \"a sine wave\"
  (params
   (level 0.25 \"output level\")))

(let loop ((i 0)
           (acc '()))
  (when (< i 3)
    (loop (+ i 1) (cons i acc))))

(define notes '(60 63 62
                67 72))
"
  "Code as `extempore fmt' indents it, which this mode's indentation follows.")

(ert-deftest extempore-indents-as-extempore-fmt-does ()
  (with-temp-buffer
    (insert (replace-regexp-in-string "^ +" "" extempore-test-indented))
    (let ((extempore-transport 'legacy))
      (extempore-mode))
    (indent-region (point-min) (point-max))
    (should (equal (buffer-string) extempore-test-indented))))

(ert-deftest extempore-definition-bounds ()
  (with-temp-buffer
    (insert "(define a 1)\n\n(define (f x)\n  (* x 2))  \n")
    (let ((extempore-transport 'legacy))
      (extempore-mode))
    (goto-char (point-min))
    (search-forward "* x")
    (pcase-let ((`(,start . ,end) (extempore--definition-bounds)))
      (should (equal (buffer-substring start end) "(define (f x)\n  (* x 2))")))
    (goto-char (point-max))  ; after the last form
    (pcase-let ((`(,start . ,end) (extempore--definition-bounds)))
      (should (equal (buffer-substring start end) "(define (f x)\n  (* x 2))")))))

(ert-deftest extempore-legacy-transport-sends-a-form-per-line ()
  (let* ((extempore-transport 'legacy)
         (received "")
         (server (make-network-process
                  :name "fake eval server" :server t :host 'local :service t
                  :filter (lambda (proc string)
                            (setq received (concat received string))
                            (process-send-string proc "40\n"))))
         (port (process-contact server :service)))
    (unwind-protect
        (with-temp-buffer
          (extempore-mode)
          (insert "(define a\n  40)\n")
          (should-error (extempore-send-buffer) :type 'user-error)
          (extempore-connect "localhost" port)
          (should (equal mode-line-process (format " localhost:%d" port)))
          (extempore-send-buffer)
          (with-timeout (5 (ert-fail "nothing arrived"))
            (while (string-empty-p received)
              (accept-process-output nil 0.05)))
          (should (equal received "(define a\n  40)\r\n"))
          (extempore-disconnect)
          (should-not extempore-connection))
      (delete-process server))))

(defun extempore-test--with-server (text body)
  "Visit TEXT in an `extempore-mode' buffer with Eglot connected, and run BODY."
  (let* ((dir (make-temp-file "extempore-test" t))
         (file (expand-file-name "song.xtm" dir))
         (extempore-program extempore-test-program)
         (extempore-nrepl-port extempore-test-port)
         (eglot-sync-connect t))
    (with-temp-file file (insert text))
    (let ((buffer (find-file-noselect file)))
      (unwind-protect
          (with-current-buffer buffer
            (apply #'eglot (eglot--guess-contact))
            (funcall body))
        (with-current-buffer buffer
          (when (eglot-current-server)
            (eglot-shutdown (eglot-current-server))))
        (kill-buffer buffer)
        (delete-directory dir t)))))

(defun extempore-test--next-result ()
  "Wait for the next result shown in this buffer, and give its text."
  (extempore--clear-results)
  (with-timeout (60 (ert-fail "no result"))
    (while (null extempore--results)
      (accept-process-output nil 0.05)))
  (substring-no-properties (overlay-get (car extempore--results) 'after-string) 1))

(ert-deftest extempore-eval-through-the-language-server ()
  (skip-unless (and extempore-test-program extempore-test-port))
  (extempore-test--with-server
   "(define answer 40)\n\n(+ answer\n   2)\n\n(car 5)\n"
   (lambda ()
     (goto-char (point-min))
     (extempore-send-definition)
     (should (equal (extempore-test--next-result) "=> 40"))
     (search-forward "answer\n")
     (extempore-send-definition)
     (should (equal (extempore-test--next-result) "=> 42"))
     ;; an edit since the last change was sent is evaluated as it stands
     (goto-char (point-max))
     (insert "(* answer 2)\n")
     (backward-char 2)
     (extempore-send-definition)
     (should (equal (extempore-test--next-result) "=> 80"))
     (goto-char (point-min))
     (search-forward "(car")
     (extempore-send-definition)
     (should (string-match-p "car argument, 5, is an integer" (extempore-test--next-result))))))

(ert-deftest extempore-eval-buffer-marks-the-form-which-failed ()
  (skip-unless (and extempore-test-program extempore-test-port))
  (extempore-test--with-server
   "(define b 1)\n(car b)\n(+ 1 2)\n"
   (lambda ()
     (extempore-send-buffer)
     (should (string-match-p "car argument" (extempore-test--next-result)))
     (let ((overlay (car extempore--results)))
       (should (= (line-number-at-pos (overlay-start overlay)) 2))))))

(provide 'extempore-mode-test)

;;; extempore-mode-test.el ends here
