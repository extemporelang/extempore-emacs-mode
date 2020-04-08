# Extempore Emacs Mode

A major mode for editing Extempore code. See the Extempore project page at
http://github.com/digego/extempore for more details.

## Installation

Available through MELPA:

    M-x package-install RET extempore-mode RET

If you don't want to get it from MELPA, just download the file and use
`package-install-file` (or even just `load`).

    (package-install-file "/path/to/extempore-mode.el")

## Usage

The most important commands are

    M-x extempore-connect (C-c C-j)

Connect the current `extempore-mode` buffer to a running Extempore
process---this is necessary to begin sending code for evaluation. If called with
a prefix arg, prompt for a host & port number to connect to, otherwise use the
values of `extempore-default-host` (default `"localhost"`) and
`extempore-default-port` (default `7099`).

An Extempore process may have multiple connected buffers, and each buffer can be
connected to multiple Extempore processes.

    M-x switch-to-extempore (C-c C-z)

Switch to the Extempore process buffer running in Emacs. If not currently
running, prompt to start one.

    M-x extempore-send-definition (C-c C-c, C-M-x)

Send the Extempore form under point (or current region, if active) to all
Extempore processes connected to the current buffer.

## Caveats

`extempore-mode` requires Emacs 24, because it inherits from `prog-mode` (via
`lisp-mode`)

## Licence

Copyright (C) 2020  Ben Swift

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
