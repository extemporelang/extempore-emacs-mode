# Extempore Emacs mode

A major mode for editing [Extempore](https://extemporelang.github.io) code. It
needs Emacs 29.1 or later.

## Installation

From MELPA: <kbd>M-x</kbd> `package-install` <kbd>RET</kbd> `extempore-mode`
<kbd>RET</kbd>. Or download `extempore-mode.el` and use `package-install-file`.

The `extempore` binary should be on your `exec-path`, or set
`extempore-program` to its path.

## Evaluating code

By default (`extempore-transport` is `nrepl`) the mode starts
[Eglot](https://www.gnu.org/software/emacs/manual/html_node/eglot/) with
Extempore's language server, `extempore lsp`. That connects to a running
Extempore's [nREPL server](https://extemporelang.github.io/guides/nrepl/),
which it finds as `extempore send` does: `$EXTEMPORE_NREPL_PORT`, then a
`.nrepl-port` file in the file's directory or above it, then port 7888. Set
`extempore-nrepl-port` (and `extempore-nrepl-host`) to say otherwise, and
`extempore-nrepl-process` to evaluate in another Scheme process, such as
`"utility"`.

| command                            | key                         |                                                  |
| ---------------------------------- | --------------------------- | ------------------------------------------------ |
| `extempore-send-dwim`              | <kbd>C-M-x</kbd>            | the region, or the top-level form at point       |
| `extempore-send-definition`        | <kbd>C-c C-c</kbd>          | the top-level form at point                      |
| `extempore-send-last-sexp`         | <kbd>C-x C-e</kbd>          | the expression before point                      |
| `extempore-send-region`            | <kbd>C-c C-r</kbd>          | the region                                       |
| `extempore-send-buffer`            | <kbd>C-c C-k</kbd>          | the buffer, as it stands                         |
| `extempore-interrupt`              | <kbd>C-c C-b</kbd>          | stop the evaluation which is running             |
| `switch-to-extempore`              | <kbd>C-c C-z</kbd>          | go to the `*extempore*` buffer, or start Extempore there |
| `extempore-repl`                   | <kbd>C-c C-e</kbd>          | a REPL on the running Extempore (`extempore repl`) |
| `extempore-format-buffer`          |                             | format with `extempore fmt`                      |

Evaluation doesn't block Emacs. Each result shows in the echo area and at the
end of its form until you next edit the buffer (`extempore-show-results-inline`
turns that off). Errors are also marked as diagnostics, and what the code
prints goes to the `*extempore output*` buffer. Eglot adds completion, eldoc
from the server's hover, and <kbd>M-x</kbd> `eglot-format`.

`extempore-run` starts Extempore in the `*extempore*` buffer, in
`extempore-path` with `extempore-program-args` (it asks for whichever isn't
set). Set `extempore-format-on-save` to format each file as it's saved.

## The legacy transport

Extempore releases before the nREPL server only accept code over a socket on
port 7099. Set `extempore-transport` to `legacy`, then connect a buffer with
<kbd>C-c C-j</kbd> (`extempore-connect`; with a prefix argument it asks for
the host and port). `extempore-disconnect` closes the connection.

## Tests

```sh
emacs -Q --batch -L . -l test/extempore-mode-test.el -f ert-run-tests-batch-and-exit
```

The tests which evaluate need `EXTEMPORE_TEST_PROGRAM` (an `extempore` binary)
and `EXTEMPORE_TEST_PORT` (the nREPL port of a running Extempore), and are
skipped without them.

## Licence

Copyright (C) 2021  Ben Swift

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
