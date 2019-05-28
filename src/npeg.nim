
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
import json
import npeg/[common,patt,stack,codegen,capture,buildpatt,grammar,dot]

export NPegException, Parser, MatchResult, contains


# Create a parser for a PEG grammar

macro peg*(name: string, n: untyped): untyped =
  var dot = newDot(name.strVal)
  var grammar = parseGrammar(n, dot)
  dot.dump()
  grammar.link(name.strVal()).genCode()


# Create a parser for a single PEG pattern

macro patt*(n: untyped): untyped =
  var grammar = newGrammar()
  var patt = parsePatt("anonymous", n, grammar)
  grammar.add("anonymous", patt)
  grammar.link("anonymous").genCode()


proc match*(p: Parser, s: string): MatchResult =
  p.fn(s)


when defined(windows) or defined(posix):
  proc matchFile*(p: Parser, fname: string): MatchResult =
    let s = readFile(fname)
    result = p.fn(s)

# Return all plain string captures from the match result

proc captures*(mr: MatchResult): seq[string] =
  collectCaptures(mr.cs)


# Return a tree with Json captures from the match result

proc capturesJson*(mr: MatchResult): JsonNode =
  collectCapturesJson(mr.cs)


