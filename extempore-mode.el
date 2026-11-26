;;; extempore-mode.el --- Major mode for Extempore source files  -*- lexical-binding: t -*-

;; Author: Ben Swift <ben@benswift.me>
;; Version: 2.0
;; Keywords: languages, lisp, extempore
;; URL: https://github.com/extemporelang/extempore-emacs-mode
;; Package-Requires: ((emacs "29.1"))

;; Copyright (c) 2011-2015, Andrew Sorensen

;; All rights reserved.

;; Redistribution and use in source and binary forms, with or without
;; modification, are permitted provided that the following conditions
;; are met:

;; 1. Redistributions of source code must retain the above copyright
;;    notice, this list of conditions and the following disclaimer.

;; 2. Redistributions in binary form must reproduce the above
;;    copyright notice, this list of conditions and the following
;;    disclaimer in the documentation and/or other materials provided
;;    with the distribution.

;; Neither the name of the authors nor other contributors may be used
;; to endorse or promote products derived from this software without
;; specific prior written permission.

;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
;; "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
;; LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
;; FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
;; COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
;; INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
;; (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
;; SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
;; HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
;; STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
;; ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
;; OF THE POSSIBILITY OF SUCH DAMAGE.

;;; Commentary:

;; A major mode for editing Extempore code (https://extemporelang.github.io).
;;
;; With Extempore's nREPL transport (the default), the mode starts Eglot with
;; Extempore's language server, `extempore lsp', which connects to a running
;; Extempore's nREPL server (found through a .nrepl-port file, else port
;; 7888).  That gives evaluation with each result shown at its form, errors
;; marked as diagnostics, completion, eldoc from hover, and formatting.
;;
;; The most important commands are
;;
;;   C-M-x      `extempore-send-dwim': evaluate the top-level form at point,
;;              or the region
;;   C-c C-k    `extempore-send-buffer'
;;   C-c C-b    `extempore-interrupt'
;;   C-c C-z    `switch-to-extempore': start Extempore in a buffer, or go to it
;;
;; For an Extempore older than its nREPL server, set `extempore-transport' to
;; `legacy' and connect to its eval server on port 7099 with C-c C-j.
;;
;; See README.md for more.

;;; Code:

(require 'lisp-mode)
(require 'cl-lib)
(require 'subr-x)
(require 'comint)
(require 'eglot)
(require 'jsonrpc)

(defgroup extempore nil
  "Editing Extempore code."
  :link '(url-link "https://extemporelang.github.io")
  :group 'languages)

(defcustom extempore-transport 'nrepl
  "How code gets to Extempore.
`nrepl' evaluates through Eglot and Extempore's language server, which talks to
Extempore's nREPL server.  `legacy' sends code over a socket to the eval server
on port 7099, for an Extempore older than the nREPL server."
  :type '(choice (const :tag "nREPL, through the language server" nrepl)
                 (const :tag "Legacy eval server" legacy)))

(defcustom extempore-program "extempore"
  "The extempore binary: a name on variable `exec-path', or a path to it."
  :type 'string)

(defcustom extempore-path nil
  "The Extempore directory, where `extempore-run' starts Extempore.
If nil, `extempore-run' asks."
  :type '(choice (const :tag "Ask" nil) directory))

(defcustom extempore-program-args nil
  "Arguments to pass to the extempore process started by `extempore-run'."
  :type '(choice (const nil) string))

(defcustom extempore-nrepl-port nil
  "The port of Extempore's nREPL server.
If nil, the language server looks for it as `extempore send' does:
$EXTEMPORE_NREPL_PORT, then a .nrepl-port file in the file's directory or
above it, then 7888."
  :type '(choice (const :tag "Find it" nil) integer))

(defcustom extempore-nrepl-host "127.0.0.1"
  "The host of Extempore's nREPL server."
  :type 'string)

(defcustom extempore-nrepl-process nil
  "The Scheme process to evaluate in, such as \"utility\".
If nil, the primary process."
  :type '(choice (const :tag "Primary" nil) string))

(defcustom extempore-default-host "localhost"
  "The host of the legacy eval server."
  :type 'string)

(defcustom extempore-default-port 7099
  "The port of the legacy eval server."
  :type 'integer)

(defcustom extempore-show-results-inline t
  "Non-nil to show each result at the end of its form until the next edit."
  :type 'boolean)

(defface extempore-blink-face
  '((t (:inherit highlight)))
  "Face which briefly marks code as it is sent.")

(defface extempore-result-face
  '((t (:inherit shadow)))
  "Face for a result shown at its form.")

(defface extempore-error-face
  '((t (:inherit error)))
  "Face for an error shown at its form.")

(defvar extempore-blink-duration 0.15
  "Seconds for which `extempore-blink-face' marks code as it is sent.")

(defun extempore--program ()
  "The extempore binary, as a path."
  (or (executable-find extempore-program)
      (and extempore-path
           (executable-find (expand-file-name "extempore" extempore-path)))
      (user-error "Can't find %s: set `extempore-program'" extempore-program)))

(defvar extempore-mode-syntax-table
  (let ((st (make-syntax-table))
        (i 0))
    ;; Symbol constituents
    (while (< i ?0)
      (modify-syntax-entry i "_   " st)
      (setq i (1+ i)))
    (setq i (1+ ?9))
    (while (< i ?A)
      (modify-syntax-entry i "_   " st)
      (setq i (1+ i)))
    (setq i (1+ ?Z))
    (while (< i ?a)
      (modify-syntax-entry i "_   " st)
      (setq i (1+ i)))
    (setq i (1+ ?z))
    (while (< i 128)
      (modify-syntax-entry i "_   " st)
      (setq i (1+ i)))
    ;; Whitespace
    (modify-syntax-entry ?\t "    " st)
    (modify-syntax-entry ?\n ">   " st)
    (modify-syntax-entry ?\f "    " st)
    (modify-syntax-entry ?\r "    " st)
    (modify-syntax-entry ?\s "    " st)
    ;; paren delimiters
    (modify-syntax-entry ?\( "()  " st)
    (modify-syntax-entry ?\) ")(  " st)
    ;; comment delimiters
    (modify-syntax-entry ?\; "<   " st)
    (modify-syntax-entry ?\" "\"   " st)
    (modify-syntax-entry ?' "'   " st)
    (modify-syntax-entry ?` "'   " st)
    ;; in xtlang, commas are used in type annotations
    (modify-syntax-entry ?, "_   " st)
    ;; Special characters
    (modify-syntax-entry ?@ "'   " st)
    (modify-syntax-entry ?# "'   " st)
    (modify-syntax-entry ?\\ "\\   " st)
    st))

(defvar extempore-mode-abbrev-table nil)
(define-abbrev-table 'extempore-mode-abbrev-table ())

(defvar extempore-imenu-generic-expression
  '(("scheme"
     "(\\(define\\|macro\\|define-macro\\)\\s-+(?\\(\\S-+\\)\\_>" 2)
    ("instrument"
     "(make-instrument\\s-+\\(\\S-+\\)\\_>" 1)
    ("lib" ;; bind-lib
     "(bind-lib\\s-+\\S-+\\s-+\\(\\S-+\\)\\_>" 1)
    ("type"
     "(bind-\\(type\\|alias\\)\\s-+\\(\\S-+\\)\\_>" 2)
    ("type" ;; bind-lib-type
     "(bind-lib-\\(type\\|alias\\)\\s-+\\(\\S-+\\)\\s-+\\(\\S-+\\)\\_>" 3)
    ("val"
     "(bind-val\\s-+\\(\\S-+\\)\\_>" 1)
    ("val" ;; bind-lib-val
     "(bind-lib-val\\s-+\\(\\S-+\\)\\s-+\\(\\S-+\\)\\_>" 2)
    ("func"
     "(bind-func\\s-+\\(static\\s-+\\)?\\(\\S-+\\)\\_>" 2)
    ("func" ;; bind-lib-func
     "(bind-lib-func\\s-+\\(\\S-+\\)\\s-+\\(\\S-+\\)\\_>" 2))
  "Imenu generic expression for Extempore mode.  See `imenu-generic-expression'.")

(defun extempore-mode-variables ()
  "Set the buffer-local variables of `extempore-mode'."
  (set-syntax-table extempore-mode-syntax-table)
  (setq local-abbrev-table extempore-mode-abbrev-table)
  (set (make-local-variable 'paragraph-start) (concat "$\\|" page-delimiter))
  (set (make-local-variable 'paragraph-separate) paragraph-start)
  (set (make-local-variable 'paragraph-ignore-fill-prefix) t)
  (set (make-local-variable 'fill-paragraph-function) 'lisp-fill-paragraph)
  ;; Adaptive fill mode gets in the way of auto-fill,
  ;; and should make no difference for explicit fill
  ;; because lisp-fill-paragraph should do the job.
  (set (make-local-variable 'adaptive-fill-mode) nil)
  (set (make-local-variable 'indent-line-function) 'extempore-indent-line)
  (set (make-local-variable 'indent-tabs-mode) nil)
  (set (make-local-variable 'parse-sexp-ignore-comments) t)
  (set (make-local-variable 'outline-regexp) ";;; \\|(....")
  (set (make-local-variable 'comment-start) ";")
  (set (make-local-variable 'comment-add) 1)
  ;; Look within the line for a ; following an even number of backslashes
  ;; after either a non-backslash or the line beginning.
  (set (make-local-variable 'comment-start-skip)
       "\\(\\(^\\|[^\\\\\n]\\)\\(\\\\\\\\\\)*\\);+[ \t]*")
  (set (make-local-variable 'font-lock-comment-start-skip) ";+ *")
  (set (make-local-variable 'comment-column) 40)
  (set (make-local-variable 'parse-sexp-ignore-comments) t)
  (set (make-local-variable 'lisp-indent-function) 'extempore-indent-function)
  ;; (set (make-local-variable 'imenu-case-fold-search) t)
  (setq imenu-generic-expression extempore-imenu-generic-expression)
  (set (make-local-variable 'font-lock-defaults)
       '(extempore-font-lock-keywords
	 nil t (("+-*/,.<>=!?$%_&~^:" . "w") (?#. "w 14"))
	 beginning-of-defun
	 (font-lock-mark-block-function . mark-defun)
	 (font-lock-syntactic-face-function
	  . extempore-font-lock-syntactic-face-function)
	 (parse-sexp-lookup-properties . t)
	 (font-lock-extra-managed-props syntax-table)))
  (set (make-local-variable 'lisp-doc-string-elt-property)
       'extempore-doc-string-elt))

(defvar-keymap extempore-mode-map
  :doc "Keymap for Extempore mode."
  :parent lisp-mode-shared-map
  "C-M-x" #'extempore-send-dwim
  "C-c C-c" #'extempore-send-definition
  "C-x C-e" #'extempore-send-last-sexp
  "C-c C-r" #'extempore-send-region
  "C-c C-k" #'extempore-send-buffer
  "C-c C-b" #'extempore-interrupt
  "C-c M-e" #'extempore-send-definition-and-go
  "C-c C-z" #'switch-to-extempore
  "C-c C-e" #'extempore-repl
  "C-c C-j" #'extempore-connect)

;;;###autoload
(define-derived-mode extempore-mode prog-mode "Extempore"
  "Major mode for editing Extempore code.

With `extempore-transport' `nrepl' it starts Eglot with Extempore's language
server, through which code is evaluated.

\\{extempore-mode-map}"
  (extempore-mode-variables)
  (add-hook 'before-save-hook #'extempore--format-before-save nil t)
  (add-hook 'after-change-functions #'extempore--clear-results nil t)
  (when (and (eq extempore-transport 'nrepl)
             (executable-find extempore-program))
    (eglot-ensure)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.xtm\\'" . extempore-mode))

(defun extempore--eglot-contact (_interactive)
  "How Eglot starts Extempore's language server."
  (list (extempore--program) "lsp"
        :initializationOptions
        `(:host ,extempore-nrepl-host
          :evalResults "response"
          ,@(and extempore-nrepl-port (list :port extempore-nrepl-port))
          ,@(and extempore-nrepl-process (list :process extempore-nrepl-process)))))

(add-to-list 'eglot-server-programs '(extempore-mode . extempore--eglot-contact))

(defcustom extempore-format-on-save nil
  "Non-nil to format the buffer with `extempore fmt' before saving it."
  :type 'boolean
  :group 'extempore)

(defun extempore-format-buffer ()
  "Format the buffer with `extempore fmt', which changes only whitespace.
It indents as this mode does, so this tidies what's been typed or pasted."
  (interactive)
  (let ((output (generate-new-buffer " *extempore-fmt*"))
        (errors (make-temp-file "extempore-fmt"))
        (coding-system-for-read 'utf-8)
        (coding-system-for-write 'utf-8))
    (unwind-protect
        (if (zerop (call-process-region (point-min) (point-max) (extempore--program)
                                        nil (list output errors) nil "fmt"))
            (unless (zerop (compare-buffer-substrings nil nil nil output nil nil))
              ;; obsolete in Emacs 31, whose replacement takes other arguments
              ;; in earlier versions; it keeps point and markers where they were
              (with-suppressed-warnings ((obsolete replace-buffer-contents))
                (replace-buffer-contents output)))
          (message "extempore fmt: %s"
                   (with-temp-buffer
                     (insert-file-contents errors)
                     (replace-regexp-in-string "\n+\\'" "" (buffer-string)))))
      (kill-buffer output)
      (delete-file errors))))

(defun extempore--format-before-save ()
  "Format the buffer if `extempore-format-on-save' is set."
  (when extempore-format-on-save
    (extempore-format-buffer)))

;;; Syntax highlighting

(defconst extempore-font-lock-keywords-scheme
  ;; scheme language builtin & function names - used for font locking
  ;; (colouring).
  ;; This list is curated by hand - it's usually pretty up to date,
  ;; but shouldn't be relied on as an Extempore language reference.
  (eval-when-compile
    (let ((extempore-builtin-names '("or" "and" "let" "lambda" "if" "else" "dotimes" "doloop" "while" "cond" "begin" "syntax-rules" "syntax" "map" "do" "letrec-syntax" "letrec" "eval" "apply" "quote" "quasiquote" "let-syntax" "let*" "for-each" "case" "call-with-output-file" "call-with-input-file" "call/cc" "call-with-current-continuation" "memzone" "letz" "catch"))
          (extempore-scheme-names '("set!" "caaaar" "cdaaar" "cadaar" "cddaar" "caadar" "cdadar" "caddar" "cdddar" "caaadr" "cdaadr" "cadadr" "cddadr" "caaddr" "cdaddr" "cadddr" "cddddr" "caaar" "cdaar" "cadar" "cddar" "caadr" "cdadr" "caddr" "cdddr" "caar" "cdar" "cadr" "cddr" "car" "cdr" "print" "println" "printout" "load" "gensym" "tracing" "make-closure" "defined?" "inexact->exact" "exp" "log" "sin" "cos" "tan" "asin" "acos" "atan" "sqrt" "expt" "floor" "ceiling" "truncate" "round" "+" "-" "*" "/" "%" "bitwise-not" "bitwise-and" "bitwise-or" "bitwise-eor" "bitwise-shift-left" "bitwise-shift-right" "quotient" "remainder" "modulo" "car" "cdr" "cons" "set-car!" "set-cdr!" "char->integer" "integer->char" "char-upcase" "char-downcase" "symbol->string" "atom->string" "string->symbol" "string->atom" "sexpr->string" "string->sexpr" "real->integer" "make-string" "string-length" "string-ref" "string-set!" "string-append" "substring" "vector" "make-vector" "vector-length" "vector-ref" "vector-set!" "not" "boolean?" "eof-object?" "null?" "=" "<" ">" "<=" ">=" "member" "equal?" "eq?" "eqv?" "symbol?" "number?" "string?" "integer?" "real?" "rational?" "char?" "char-alphabetic?" "char-numeric?" "char-whitespace?" "char-upper-case?" "char-lower-case?" "port?" "input-port?" "output-port?" "procedure?" "pair?" "list?" "environment?" "vector?" "cptr?" "eq?" "eqv?" "force" "write" "write-char" "display" "emit" "newline" "error" "reverse" "list*" "append" "put" "get" "quit" "new-segment" "oblist" "sexp-bounds-port" "current-output-port" "open-input-file" "open-output-file" "open-input-output-file" "open-input-string" "open-output-string" "open-input-output-string" "close-input-port" "close-output-port" "interaction-environment" "current-environment" "read" "read-char" "peek-char" "char-ready?" "set-input-port" "set-output-port" "length" "assq" "get-closure-code" "closure?" "macro?" "macro-expand" "foldl" "foldr")))
      (list
       ;; other type annotations (has to be first in list)
       '(":[]{}[[:alnum:]_<>,*:/|!-]+"
         (0 font-lock-type-face))
       ;; built-ins
       (list
        (concat
         "("
         (regexp-opt extempore-builtin-names t)
         "\\>")
        '(1 font-lock-keyword-face t))
       ;; float and int literals
       '("\\_<[-+]?[/.[:digit:]]+?\\_>"
         (0 font-lock-constant-face))
       ;; hex/oct/binary literals
       '("\\_<#[xob][0-9a-fA-F]+?\\_>"
         (0 font-lock-constant-face))
       ;; scientific notation e.g. 1 million = 1e6
       '("\\_<[[:digit:]]+?e[[:digit:]]+?\\_>"
         (0 font-lock-constant-face))
       ;; hack to make sure / gets highlighted as a function
       '("\\_</\\_>"
         (0 font-lock-function-name-face t))
       ;; boolean literals
       '("\\_<#[tf]\\_>"
         (0 font-lock-constant-face))
       ;; definitions
       (list (concat
              "(\\(define\\|macro\\|define-macro\\|define-syntax\\|make-instrument\\)\\_>\\s-*(?\\(\\sw+\\)?")
             '(1 font-lock-keyword-face)
             '(2 font-lock-function-name-face))
       ;; scheme functions
       (list
        (regexp-opt extempore-scheme-names 'symbols)
        '(1 font-lock-function-name-face))
       ;; It wouldn't be Scheme w/o named-let.
       '("(let\\s-+\\(\\sw+\\)"
         (1 font-lock-function-name-face))))))

(defconst extempore-font-lock-keywords-xtlang
  ;; xtlang language builtin names - used for font locking (colouring).
  ;; This list is curated by hand - it's usually pretty up to date,
  ;; but shouldn't be relied on as an Extempore language reference.
  (eval-when-compile
    (let ((extempore-xtlang-names '("random" "afill!" "pfill!" "tfill!" "vfill!" "array-fill!" "pointer-fill!" "tuple-fill!" "vector-fill!" "free" "array" "tuple" "list" "~" "cset!" "cref" "&" "bor" "ang-names" "<<" ">>" "nil" "printf" "sprintf" "null" "now" "pset!" "pref-ptr" "vset!" "vref" "aset!" "aref" "aref-ptr" "tset!" "tref" "tref-ptr" "salloc" "halloc" "zalloc" "alloc" "schedule" "exp" "log" "sin" "cos" "tan" "asin" "acos" "atan" "atan2" "sqrt" "expt" "floor" "ceiling" "truncate" "round" "llvm_printf" "push_zone" "pop_zone" "memzone" "callback" "llvm_sprintf" "make-array" "array-set!" "array-ref" "array-ref-ptr" "pointer-set!" "pointer-ref" "pointer-ref-ptr" "stack-alloc" "heap-alloc" "zone-alloc" "make-tuple" "tuple-set!" "tuple-ref" "tuple-ref-ptr" "closure-set!" "closure-ref" "pref" "pdref" "impc_null" "bitcast" "void" "ifret" "ret->" "clrun->" "make-env-zone" "make-env" "<>")))
      (list
       ;; xtlang "keywords"
       (list
        (regexp-opt extempore-xtlang-names 'symbols)
        '(1 font-lock-function-name-face))
       ;; bind-func
       '("(\\(bind-func\\)\\s-+\\([[:alnum:]_-]+\\)"
         (1 font-lock-keyword-face)
         (2 font-lock-function-name-face))
       '("(\\(bind-macro\\)"
         (1 font-lock-keyword-face))
       '("(\\(bind-poly\\)\\s-+\\([[:alnum:]_-]+\\)\\s-+\\([[:alnum:]_-]+\\)"
         (1 font-lock-keyword-face)
         (2 font-lock-constant-face t)
         (3 font-lock-function-name-face))
       
       ;; bind-alias
       '("(\\(bind-alias\\)\\s-+\\([[:alnum:]_-]+\\)\\s-+\\([]{}[[:alnum:]_<>,*:/|-]+\\)"
         (1 font-lock-keyword-face)
         (2 font-lock-function-name-face)
         (3 font-lock-type-face))
       ;; bind-type
       '("(\\(bind-type\\)\\s-+\\([[:alnum:]_-]+\\)\\s-+\\([]{}[[:alnum:]_<>,*:/|!-]+\\)"
         (1 font-lock-keyword-face)
         (2 font-lock-function-name-face)
         (3 font-lock-type-face))
       ;; bind-dylib
       '("(\\(bind-dylib\\)\\s-+\\([[:alnum:]_-]+\\)"
         (1 font-lock-keyword-face)
         (2 font-lock-constant-face))
       ;; bind-lib
       '("(\\(bind-lib\\)\\s-+\\([[:alnum:]_-]+\\)\\s-+\\([[:alnum:]_-]+\\)\\s-+\\([]{}[[:alnum:]_<>,*:/|-]+\\)"
         (1 font-lock-keyword-face)
         (2 font-lock-constant-face)
         (3 font-lock-function-name-face)
         (4 font-lock-type-face))
       ;; bind-lib-type
       '("(\\(bind-lib-type\\)\\s-+\\([[:alnum:]_-]+\\)\\s-+\\([[:alnum:]_-]+\\)\\s-+\\([]{}[[:alnum:]_<>,*:/|-]+\\)"
         (1 font-lock-keyword-face)
         (2 font-lock-constant-face)
         (3 font-lock-function-name-face)
         (4 font-lock-type-face))
       ;; bind-lib-func
       '("(\\(bind-lib-func\\)\\s-+\\([[:alnum:]_-]+\\)\\s-+\\([[:alnum:]_-]+\\)\\s-+\\([]{}[[:alnum:]_<>,*:/|-]+\\)"
         (1 font-lock-keyword-face)
         (2 font-lock-constant-face)
         (3 font-lock-function-name-face)
         (4 font-lock-type-face))
       ;; bind-val
       '("(\\(bind-val\\)\\s-+\\([[:alnum:]_-]+\\)\\s-+\\([]{}[[:alnum:]_<>,*:/|-]+\\)"
         (1 font-lock-keyword-face)
         (2 font-lock-function-name-face)
         (3 font-lock-type-face))
       ;; bind-lib-val
       '("(\\(bind-lib-val\\)\\s-+\\([[:alnum:]_-]+\\)\\s-+\\([[:alnum:]_-]+\\)\\s-+\\([]{}[[:alnum:]_<>,*:/|-]+\\)"
         (1 font-lock-keyword-face)
         (2 font-lock-constant-face)
         (3 font-lock-function-name-face)
         (4 font-lock-type-face))
       ;; cast
       '("(\\(cast\\|convert\\)\\s-+\\S-+\\s-+\\([^ \t)]?+\\))"
         (1 font-lock-keyword-face)
         (2 font-lock-type-face))
       '("(\\(constrain-genericfunc\\|specialize-genericfunc\\|specialize-generictype\\)\\s-+\\(\\S-+\\)\\s-+\\([^)]?+\\))"
         (1 font-lock-keyword-face)
         (2 font-lock-function-name-face)
         (3 font-lock-type-face))
       ;; type coercion stuff
       (list
        (concat
         "(" (regexp-opt
              (let ((types '("i1" "i8" "i16" "i32" "i64" "f" "d")))
                (apply 'append (mapcar (lambda (a)
                                         (mapcar (lambda (b)
                                                   (concat a "to" b))
                                                 (remove a types)))
                                       types))) t) "\\>")
        '(1 font-lock-type-face))))))

(defvar extempore-font-lock-keywords
  (append extempore-font-lock-keywords-scheme
          extempore-font-lock-keywords-xtlang)
  "Expressions to highlight in extempore-mode.")

(defconst extempore-sexp-comment-syntax-table
  (let ((st (make-syntax-table extempore-mode-syntax-table)))
    (modify-syntax-entry ?\; "." st)
    (modify-syntax-entry ?\n " " st)
    (modify-syntax-entry ?#  "'" st)
    st))

(put 'lambda 'extempore-doc-string-elt 2)
;; Docstring's pos in a `define' depends on whether it's a var or fun def.
(put 'define 'extempore-doc-string-elt
     (lambda ()
       ;; The function is called with point right after "define".
       (forward-comment (point-max))
       (if (eq (char-after) ?\() 2 0)))

(defun extempore-font-lock-syntactic-face-function (state)
  (when (and (null (nth 3 state))
	     (eq (char-after (nth 8 state)) ?#)
	     (eq (char-after (1+ (nth 8 state))) ?\;))
    ;; It's a sexp-comment.  Tell parse-partial-sexp where it ends.
    (save-excursion
      (let ((pos (point))
	    (end
	     (condition-case err
		 (let ((parse-sexp-lookup-properties nil))
		   (goto-char (+ 2 (nth 8 state)))
		   ;; FIXME: this doesn't handle the case where the sexp
		   ;; itself contains a #; comment.
		   (forward-sexp 1)
		   (point))
	       (scan-error (nth 2 err)))))
	(when (< pos (- end 2))
	  (put-text-property pos (- end 2)
			     'syntax-table extempore-sexp-comment-syntax-table))
	(put-text-property (- end 1) end 'syntax-table '(12)))))
  ;; Choose the face to use.
  (lisp-font-lock-syntactic-face-function state))

;;; Indentation

(defvar calculate-lisp-indent-last-sexp)

;; `extempore fmt' (Formatter.cpp in the Extempore repo) is the reference for
;; this indentation, and tree-sitter-extempore's indents.scm follows it too.

(defun extempore-indent-line ()
  "Indent the current line as Lisp code, comment lines included.
`lisp-indent-line' puts a line which starts with one semicolon at
`comment-column', and leaves one which starts with three alone."
  (if (save-excursion (beginning-of-line) (looking-at "[ \t]*;"))
      (let ((indent (save-excursion (beginning-of-line) (calculate-lisp-indent))))
        (indent-line-to (or (if (consp indent) (car indent) indent) 0)))
    (lisp-indent-line)))

(defun extempore--data-list-p (state)
  "Non-nil if the innermost list in STATE aligns with its first element.
That is a list whose head isn't a symbol (a literal, a list or a quoted form), a
vector, a quoted list, or a list inside a quoted one which isn't unquoted."
  (or (save-excursion
        (goto-char (1+ (elt state 1)))
        (skip-chars-forward " \t")
        (looking-at "[-+]?\\.?[0-9]\\|[\"('`]\\|,@?(\\|#[(\\\\]\\|#[tf]\\_>"))
      (catch 'data
        (dolist (open (reverse (elt state 9)))
          (pcase (char-before open)
            ((or ?' ?#) (throw 'data t))
            ((or ?` ?, ?@) (throw 'data nil))))
        nil)))

(defun extempore--specform-indent (count state indent-point _normal-indent)
  "The indentation inside a form which distinguishes COUNT arguments from its body.
The body indents two columns from the form's parenthesis, and a distinguished
argument on a line of its own four. When more than COUNT arguments share the
head's line, the body aligns with the first of the rest (where
`lisp-indent-specform' aligns it with the first argument)."
  (save-excursion
    (let ((open (elt state 1))
          (before 0)
          (on-head-line 0)
          column head-line)
      (goto-char (1+ open))
      (forward-sexp 1)
      (setq head-line (line-number-at-pos))
      (condition-case nil
          (while (progn (forward-comment (buffer-size)) (< (point) indent-point))
            (let ((start (point)))
              ;; , and ,@ are symbol constituents here (for xtlang's types),
              ;; so step over an unquote's mark to read it as one sexp
              (when (looking-at ",@?[([]")
                (goto-char (match-end 0))
                (backward-char 1))
              (forward-sexp 1)
              (setq before (1+ before))
              (when (= (line-number-at-pos start) head-line)
                (setq on-head-line (1+ on-head-line))
                (when (= on-head-line (1+ count))
                  (setq column (save-excursion (goto-char start) (current-column)))))))
        (error nil))
      (goto-char open)
      (cond (column column)
            ((and (< before count)
                  (save-excursion
                    (goto-char indent-point)
                    (skip-chars-forward " \t")
                    (not (looking-at "[);]"))))
             (+ (current-column) 4))
            (t (+ (current-column) 2))))))

(defun extempore--call-indent (state indent-point)
  "The indentation inside a call, the innermost list in STATE.
Aligned with the first argument when that shares the head's line, and with
the head when it doesn't."
  (save-excursion
    (goto-char (1+ (elt state 1)))
    (skip-chars-forward " \t")
    (let ((head-column (current-column)))
      (forward-sexp 1)
      (let ((head-line (line-number-at-pos)))
        (forward-comment (buffer-size))
        (if (and (< (point) indent-point) (= (line-number-at-pos) head-line))
            (current-column)
          head-column)))))

(defun extempore--body-indent (state)
  "Two columns from the parenthesis of the innermost list in STATE."
  (save-excursion
    (goto-char (elt state 1))
    (+ (current-column) 2)))

(defconst extempore--definition-regexp
  "\\`\\(?:define\\(?:\\*\\|[-c].*\\)?\\|def-.*\\|with-.*\\)\\'"
  "A name whose body indents two columns, after any namespace: define, define*,
define-macro, definec, def-instrument, with-... (but not defined? or default).")

(defun extempore--first-element-column (state indent-point)
  "The column of the first element of the innermost list in STATE.
One past its parenthesis when that element starts on INDENT-POINT's line."
  (save-excursion
    (goto-char (1+ (elt state 1)))
    (forward-comment (buffer-size))
    (if (>= (point) indent-point)
        (progn (goto-char (elt state 1)) (1+ (current-column)))
      (current-column))))

;; FIXME this duplicates almost all of lisp-indent-function.
;; Extract common code to a subroutine.
(defun extempore-indent-function (indent-point state)
  "Extempore mode function for the value of the variable `lisp-indent-function'.
This behaves like the function `lisp-indent-function', except that:

i) it checks for a non-nil value of the property `extempore-indent-function'
\(or the deprecated `extempore-indent-hook'), rather than `lisp-indent-function'.

ii) if that property specifies a function, it is called with three
arguments (not two), the third argument being the default (i.e., current)
indentation."
  (if (extempore--data-list-p state)
      (extempore--first-element-column state indent-point)
  (let ((normal-indent (current-column)))
    (goto-char (1+ (elt state 1)))
    (parse-partial-sexp (point) calculate-lisp-indent-last-sexp 0 t)
    (if (and (elt state 2)
	     (not (looking-at "\\sw\\|\\s_")))
	;; car of form doesn't seem to be a symbol
	(progn
	  (if (not (> (save-excursion (forward-line 1) (point))
		      calculate-lisp-indent-last-sexp))
	      (progn (goto-char calculate-lisp-indent-last-sexp)
		     (beginning-of-line)
		     (parse-partial-sexp (point)
					 calculate-lisp-indent-last-sexp 0 t)))
	  ;; Indent under the list or under the first sexp on the same
	  ;; line as calculate-lisp-indent-last-sexp.  Note that first
	  ;; thing on that line has to be complete sexp since we are
	  ;; inside the innermost containing sexp.
	  (backward-prefix-chars)
	  (current-column))
      (let ((function (buffer-substring (point)
					(progn (forward-sexp 1) (point))))
	    method)
	(setq method (or (get (intern-soft function) 'extempore-indent-function)
			 (get (intern-soft function) 'extempore-indent-hook)))
	(cond ((or (eq method 'defun)
		   (and (null method)
			(let ((case-fold-search nil))
			  (string-match-p extempore--definition-regexp
					  (replace-regexp-in-string "\\`.*:" "" function)))))
	       (extempore--body-indent state))
	      ((integerp method)
	       (extempore--specform-indent method state
					   indent-point normal-indent))
	      (method
               (funcall method state indent-point normal-indent))
	      (t (extempore--call-indent state indent-point))))))))


;;; 'let' is different in Scheme/xtlang

(defun would-be-symbol (string)
  (not (string-equal (substring string 0 1) "(")))

(defun next-sexp-as-string ()
  ;; Assumes that it is protected by a save-excursion
  (forward-sexp 1)
  (let ((the-end (point)))
    (backward-sexp 1)
    (buffer-substring (point) the-end)))

(defun extempore-let-indent (state indent-point normal-indent)
  (skip-chars-forward " \t")
  (if (looking-at "[-a-zA-Z0-9+*/?!@$%^&_:~]")
      (extempore--specform-indent 2 state indent-point normal-indent)
    (extempore--specform-indent 1 state indent-point normal-indent)))

;; An integer is the number of arguments a form distinguishes from its body.
;; `extempore fmt' and tree-sitter-extempore's queries/indents.scm name the
;; same forms, so that every editor indents alike: keep the three in step.

(put 'begin 'extempore-indent-function 0)
(put 'beginz 'extempore-indent-function 0)
(put 'delay 'extempore-indent-function 0)
(put 'cond 'extempore-indent-function 0)
(put 'case-lambda 'extempore-indent-function 0)
(put 'case 'extempore-indent-function 1)
(put 'when 'extempore-indent-function 1)
(put 'unless 'extempore-indent-function 1)
(put 'do 'extempore-indent-function 2)
(put 'dotimes 'extempore-indent-function 1)
(put 'doloop 'extempore-indent-function 1)
(put 'while 'extempore-indent-function 1)
(put 'lambda 'extempore-indent-function 1)
(put 'lambda* 'extempore-indent-function 1)
(put 'lambdaz 'extempore-indent-function 1)
(put 'lambdas 'extempore-indent-function 1)
(put 'lambdah 'extempore-indent-function 1)
(put 'memzone 'extempore-indent-function 1)
(put 'bind-func 'extempore-indent-function 'defun)
(put 'bind-macro 'extempore-indent-function 'defun)
(put 'bind-poly 'extempore-indent-function 'defun)
(put 'bind-type 'extempore-indent-function 'defun)
(put 'bind-data 'extempore-indent-function 'defun)
(put 'bind-alias 'extempore-indent-function 'defun)
(put 'bind-val 'extempore-indent-function 'defun)
(put 'bind-ext-val 'extempore-indent-function 'defun)
(put 'bind-lib 'extempore-indent-function 'defun)
(put 'bind-lib-val 'extempore-indent-function 'defun)
(put 'bind-dylib 'extempore-indent-function 'defun)
(put 'bind-instrument 'extempore-indent-function 'defun)
(put 'bind-sampler 'extempore-indent-function 'defun)
(put 'macro 'extempore-indent-function 'defun)
(put 'let 'extempore-indent-function 'extempore-let-indent)
(put 'letz 'extempore-indent-function 'extempore-let-indent)
(put 'let* 'extempore-indent-function 'extempore-let-indent)
(put 'letrec 'extempore-indent-function 'extempore-let-indent)
(put 'letrec* 'extempore-indent-function 1)
(put 'let-values 'extempore-indent-function 1)
(put 'let*-values 'extempore-indent-function 1)
(put 'parameterize 'extempore-indent-function 1)
(put 'guard 'extempore-indent-function 1)
(put 'receive 'extempore-indent-function 2)
(put 'let-syntax 'extempore-indent-function 1)
(put 'letrec-syntax 'extempore-indent-function 1)
(put 'syntax-rules 'extempore-indent-function 1)
(put 'syntax-case 'extempore-indent-function 2) ; not r5rs
(put 'call-with-input-file 'extempore-indent-function 1)
(put 'call-with-output-file 'extempore-indent-function 1)
(put 'call-with-values 'extempore-indent-function 1) ; r5rs?
(put 'dynamic-wind 'extempore-indent-function 3) ; r5rs?

;;; Evaluation

(defun extempore--blink (start end)
  "Mark the code from START to END briefly with `extempore-blink-face'."
  (let ((overlay (make-overlay start end)))
    (overlay-put overlay 'face 'extempore-blink-face)
    (overlay-put overlay 'priority 1000)
    (run-at-time extempore-blink-duration nil #'delete-overlay overlay)))

(defun extempore-send-region (start end)
  "Evaluate the code from START to END."
  (interactive "r")
  (if (eq extempore-transport 'legacy)
      (extempore--legacy-send (buffer-substring-no-properties start end))
    (extempore--eval "extempore.eval" start end))
  (extempore--blink start end))

(defun extempore--definition-bounds ()
  "The start and end of the top-level form at point, or else the one before it."
  (save-excursion
    (end-of-defun)
    (beginning-of-defun)
    (cons (point) (progn (forward-sexp) (point)))))

(defun extempore-send-definition ()
  "Evaluate the top-level form at point."
  (interactive)
  (pcase-let ((`(,start . ,end) (extempore--definition-bounds)))
    (extempore-send-region start end)))

(defun extempore-send-dwim ()
  "Evaluate the region if it's active, else the top-level form at point."
  (interactive)
  (if (region-active-p)
      (extempore-send-region (region-beginning) (region-end))
    (extempore-send-definition)))

(defun extempore-send-last-sexp ()
  "Evaluate the expression before point."
  (interactive)
  (extempore-send-region (save-excursion (backward-sexp) (point)) (point)))

(defun extempore-send-buffer ()
  "Evaluate the buffer as it stands, a top-level form at a time."
  (interactive)
  (if (eq extempore-transport 'legacy)
      (save-excursion
        (goto-char (point-min))
        (while (re-search-forward "^(" nil t)
          (pcase-let ((`(,start . ,end) (extempore--definition-bounds)))
            (extempore--legacy-send (buffer-substring-no-properties start end))
            (goto-char end))))
    (extempore--eval "extempore.evalBuffer"))
  (extempore--blink (point-min) (point-max)))

(defun extempore-send-definition-and-go ()
  "Evaluate the top-level form at point, then switch to the Extempore buffer."
  (interactive)
  (extempore-send-definition)
  (switch-to-extempore))

(defun extempore-interrupt ()
  "Stop the evaluation which is running."
  (interactive)
  (if (eq extempore-transport 'legacy)
      (user-error "The legacy transport can't interrupt an evaluation")
    (jsonrpc-async-request (extempore--server) :workspace/executeCommand
                           '(:command "extempore.interrupt")
                           :success-fn #'ignore :timeout nil)))

(defun extempore--server ()
  "The Eglot server for this buffer."
  (or (eglot-current-server)
      (user-error "No language server for this buffer: start it with M-x eglot")))

(defun extempore--eval (command &optional start end)
  "Ask the language server to run COMMAND, on START to END if they're given.
The result shows when the evaluation finishes; Emacs carries on meanwhile."
  (let* ((server (extempore--server))
         (buffer (current-buffer))
         (marker (and end (copy-marker end)))
         (argument (append (eglot--TextDocumentIdentifier)
                           (and start
                                (list :range
                                      (list :start (eglot--pos-to-lsp-position start)
                                            :end (eglot--pos-to-lsp-position end)))))))
    ;; the server must have the buffer as it is now
    (eglot--signal-textDocument/didChange)
    (jsonrpc-async-request
     server :workspace/executeCommand
     (list :command command :arguments (vector argument))
     :success-fn (lambda (result)
                   (when (and result (buffer-live-p buffer))
                     (with-current-buffer buffer
                       (extempore--show-result result marker))))
     :error-fn (lambda (error)
                 (message "extempore: %s" (plist-get error :message)))
     :timeout nil)))

(defun extempore--summary (result)
  "The line which says what RESULT, an evaluation's result, was."
  (let ((error (plist-get result :error))
        (values (append (plist-get result :values) nil))
        (out (string-trim (or (plist-get result :out) ""))))
    (cond ((eq (plist-get result :interrupted) t) "interrupted")
          (error (car (split-string (plist-get error :message) "\n")))
          (values (mapconcat (lambda (value) (concat "=> " value)) values "  "))
          ((string-empty-p out) "evaluated")
          (t (car (split-string out "\n"))))))

(defvar-local extempore--results nil
  "The overlays which show results in this buffer.")

(defun extempore--clear-results (&rest _)
  "Remove the results shown in this buffer."
  (mapc #'delete-overlay extempore--results)
  (setq extempore--results nil))

(defun extempore--show-result (result marker)
  "Say what RESULT was, and show it at the end of MARKER's line.
Without MARKER (the buffer was evaluated), at the form which failed, if one
did."
  (let* ((summary (extempore--summary result))
         (failed (or (plist-get result :error)
                     (eq (plist-get result :interrupted) t)))
         (face (if failed 'extempore-error-face 'extempore-result-face))
         (range (plist-get result :range))
         (at (cond (marker (marker-position marker))
                   (range (eglot--lsp-position-to-point (plist-get range :end))))))
    (extempore--log result)
    (message "%s" (propertize summary 'face face))
    (when (and at extempore-show-results-inline)
      (save-excursion
        (goto-char at)
        (let ((overlay (make-overlay (line-end-position) (line-end-position))))
          (overlay-put overlay 'after-string
                       (concat " " (propertize summary 'face face)))
          (push overlay extempore--results))))))

(defun extempore--log (result)
  "Add what RESULT printed, and its error, to the *extempore output* buffer."
  (let ((out (plist-get result :out))
        (error (plist-get (plist-get result :error) :message)))
    (with-current-buffer (get-buffer-create "*extempore output*")
      (goto-char (point-max))
      (let ((inhibit-read-only t))
        (dolist (text (list out error))
          (when (and text (not (string-empty-p text)))
            (insert text)
            (unless (bolp) (insert "\n"))))))))

;;; The legacy transport

;; Each buffer has its own connections to legacy eval servers, and sends code
;; to all of them.
(defvar-local extempore-connection-list nil
  "This buffer's connections to legacy eval servers.")

(defun extempore--update-mode-line ()
  "Show this buffer's legacy connections in the mode line."
  (setq mode-line-process
        (mapconcat (lambda (proc)
                     (let ((host (process-contact proc :host)))
                       (format " %s%d"
                               (if (string= host "localhost") "" (concat host ":"))
                               (process-contact proc :service))))
                   extempore-connection-list "")))

(defun extempore--sync-connections ()
  "Forget the connections which have closed."
  (dolist (proc extempore-connection-list)
    (unless (memq (process-status proc) '(run open))
      (setq extempore-connection-list (delq proc extempore-connection-list))
      (delete-process proc)))
  (extempore--update-mode-line))

(defun extempore--legacy-filter (_proc string)
  "Show STRING, a legacy eval server's answer, in the echo area."
  (message "%s" (string-trim-right string)))

(defun extempore-connect (host port)
  "Connect to the legacy eval server on HOST and PORT.
With a prefix argument, ask for them; otherwise use `extempore-default-host'
and `extempore-default-port'."
  (interactive
   (if current-prefix-arg
       (list (read-string "Host: " extempore-default-host)
             (read-number "Port: " extempore-default-port))
     (list extempore-default-host extempore-default-port)))
  (extempore--sync-connections)
  (if (cl-find-if (lambda (proc)
                    (and (string= host (process-contact proc :host))
                         (= port (process-contact proc :service))))
                  extempore-connection-list)
      (message "Already connected to %s:%d" host port)
    (let ((proc (open-network-stream "extempore" nil host port)))
      (set-process-coding-system proc 'utf-8-unix 'utf-8-unix)
      (set-process-filter proc #'extempore--legacy-filter)
      (setq extempore-connection-list (append extempore-connection-list (list proc)))
      (extempore--update-mode-line))))

(defvar-local extempore-multiple-connection-list nil
  "Legacy eval servers for `extempore-connect-multiple', as ((HOST . PORT) ...).")

(defun extempore-connect-multiple ()
  "Connect to every eval server in `extempore-multiple-connection-list'."
  (interactive)
  (pcase-dolist (`(,host . ,port) extempore-multiple-connection-list)
    (extempore-connect host port)))

(defun extempore-disconnect ()
  "Close this buffer's connections to legacy eval servers."
  (interactive)
  (mapc #'delete-process extempore-connection-list)
  (setq extempore-connection-list nil)
  (extempore--update-mode-line))

(defun extempore--legacy-send (code)
  "Send CODE to each of this buffer's legacy eval servers."
  (extempore--sync-connections)
  (unless extempore-connection-list
    (user-error "Not connected to an eval server: connect with C-c C-j"))
  (dolist (proc extempore-connection-list)
    (process-send-string proc (concat code "\r\n"))))

;;; Extempore in a buffer

(defvar extempore-buffer "*extempore*"
  "The buffer `extempore-run' starts Extempore in.")

(define-derived-mode inferior-extempore-mode comint-mode "Inferior Extempore"
  "Major mode for the buffer Extempore runs in."
  (setq mode-line-process '(":%s")))

(defvar extempore-run-history-list nil)

;;;###autoload
(defun extempore-run (program-args run-directory)
  "Run Extempore with PROGRAM-ARGS in RUN-DIRECTORY, in `extempore-buffer'.
Interactively, ask for both, starting from `extempore-program-args' and
`extempore-path' (a prefix argument asks for the directory when
`extempore-path' is set)."
  (interactive
   (list (read-string "Run: extempore " extempore-program-args 'extempore-run-history-list)
         (if (or current-prefix-arg (not extempore-path))
             (read-directory-name "In directory: ")
           extempore-path)))
  (unless (comint-check-proc extempore-buffer)
    (with-current-buffer (get-buffer-create extempore-buffer)
      (setq default-directory (file-name-as-directory (expand-file-name run-directory)))
      (apply #'make-comint-in-buffer "extempore" (current-buffer) (extempore--program) nil
             (split-string-and-unquote (or program-args "")))
      (inferior-extempore-mode))))

;;;###autoload
(defun switch-to-extempore ()
  "Switch to the buffer Extempore runs in, starting it if it isn't running."
  (interactive)
  (if (comint-check-proc extempore-buffer)
      (progn (pop-to-buffer extempore-buffer)
             (goto-char (point-max)))
    (call-interactively #'extempore-run)
    (display-buffer extempore-buffer)))

(defun extempore-stop ()
  "Interrupt the Extempore which `extempore-run' started."
  (interactive)
  (if (comint-check-proc extempore-buffer)
      (with-current-buffer extempore-buffer
        (comint-interrupt-subjob))
    (message "Extempore isn't running in %s" extempore-buffer)))

;;; REPL

(define-derived-mode extempore-repl-mode comint-mode "Extempore REPL"
  "Major mode for `extempore repl', a REPL on a running Extempore."
  (setq-local comint-prompt-regexp "^\\(xtm\\|\\.\\.\\.\\)> ")
  (setq-local comint-process-echoes t)
  (setq-local comint-prompt-read-only t))

;;;###autoload
(defun extempore-repl ()
  "Open a REPL on the running Extempore, through `extempore repl'."
  (interactive)
  (let ((buffer (get-buffer-create "*extempore repl*"))
        (args (append (and extempore-nrepl-port
                           (list "--port" (number-to-string extempore-nrepl-port)))
                      (and extempore-nrepl-process
                           (list "--process" extempore-nrepl-process)))))
    (unless (comint-check-proc buffer)
      (apply #'make-comint-in-buffer "extempore repl" buffer (extempore--program) nil
             "repl" args)
      (with-current-buffer buffer
        (extempore-repl-mode)))
    (pop-to-buffer buffer)))

(define-obsolete-function-alias 'extempore-find-executable #'extempore--program "2.0")
(define-obsolete-function-alias 'extempore-send-buffer-or-region #'extempore-send-dwim "2.0")
(define-obsolete-function-alias 'extempore-disconnect-all #'extempore-disconnect "2.0")

(provide 'extempore-mode)

;;; extempore-mode.el ends here
