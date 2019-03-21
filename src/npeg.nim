
#
# Copyright (c) 2019 Ico Doornekamp
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# This parser implementation is based on the following papers:
#
# - A Text Pattern-Matching Tool based on Parsing Expression Grammars
#   (Roberto Ierusalimschy)
#
# - An efficient parsing machine for PEGs
#   (Jos Craaijo)
#


import tables
import macros

import npeg/common
import npeg/patt
import npeg/stack
import npeg/codegen
import npeg/capture
import npeg/buildpatt
import npeg/grammar

export push, update, collectCaptures


# Create a parser for a single PEG pattern

macro patt*(ns: untyped): untyped =
  var symtab = newTable[string, Patt]()
  var patt = buildPatt(ns, symtab)
  patt.add Inst(op: opReturn)
  when npegTrace:
    echo patt
  genCode("p", patt)


# Create a parser for a PEG grammar

macro peg*(name: string, ns: untyped): untyped =
  let grammar = parseGrammar(ns)
  let patt = linkGrammar(grammar, name.strVal)
  when npegTrace:
    echo patt
  genCode(name.strVal, patt)


