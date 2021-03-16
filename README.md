# Extempore Emacs Mode

A major mode for editing Extempore code. See the Extempore project page at
http://github.com/digego/extempore for more details.

## Installation

Available through MELPA:

- <kbd>M-x</kbd> `package-install` <kbd>RET</kbd> `extempore-mode`
  <kbd>RET</kbd>

If you don't want to get it from MELPA, just download the file and use
`package-install-file` (or even just `load`).

    (package-install-file "/path/to/extempore-mode.el")

## Configuration

There are several config variables to tweakl, but in most cases the defaults
will be ok if you're just starting out. If you want to see them, hit
<kbd>M-x</kbd> `customize` and look in the `extempore` group.

The only thing you might want to set out-of-the-box is `extempore-path`, so that
you don't have to answer the "directory" prompt every time you call
`switch-to-extempore`. You can do it through `customize` or set it directly in
your init file like so:

    (setq extempore-path "/path/to/extempore/")

## Usage

The most important commands are

- <kbd>M-x</kbd> `extempore-connect` (<kbd>C-c</kbd> <kbd>C-j</kbd>)

Connect the current `extempore-mode` buffer to a running Extempore
process---this is necessary to begin sending code for evaluation. If called with
a prefix arg, prompt for a host & port number to connect to, otherwise use the
values of `extempore-default-host` (default `"localhost"`) and
`extempore-default-port` (default `7099`).

An Extempore process may have multiple connected buffers, and each buffer can be
connected to multiple Extempore processes.

- <kbd>M-x</kbd> `switch-to-extempore` (<kbd>C-c</kbd> <kbd>C-z</kbd>)

Switch to the Extempore process buffer running in Emacs. If not currently
running, prompt to start one.

<kbd>M-x</kbd> `extempore-send-definition` (<kbd>C-c</kbd> <kbd>C-c</kbd> or
<kbd>C-M-x</kbd>)

Send the Extempore form under point (or current region, if active) to all
Extempore processes connected to the current buffer.

## Caveats

`extempore-mode` requires Emacs 24, because it inherits from `prog-mode` (via
`lisp-mode`)

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
