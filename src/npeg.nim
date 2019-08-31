
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
import strutils
import npeg/[common,codegen,capture,parsepatt,grammar,dot]

export NPegException, Parser, MatchResult, contains

# Create a parser for a PEG grammar

proc pegAux(name: string, userDataType: NimNode, userDataId: string, n: NimNode): NimNode =
  var dot = newDot(name)
  var grammar = parseGrammar(n, dot)
  let code = grammar.link(name, dot).genCode(userDataType, ident(userDataId))
  dot.dump()
  code

macro peg*(name: untyped, n: untyped): untyped =
  let userDataType = bindSym("bool")
  pegAux(name.strVal, userDataType, "userdata", n)

macro peg*(name: untyped, userData: untyped, n: untyped): untyped =
  expectKind(userData, nnkExprColonExpr)
  expectLen(userData, 2, 2)
  pegAux name.strVal, userData[1], userData[0].strVal, n


# Create a parser for a single PEG pattern

macro patt*(n: untyped): untyped =
  quote do:
    peg "anonymous":
      anonymous <- `n`


# Define a grammar for storage in the global library.

macro grammar*(libNameNode: string, n: untyped) =
  let grammar = parseGrammar(n)
  let libName = libNameNode.strval
  libStore(libName, grammar)


# Match a subject string

proc match*[T](p: Parser, s: Subject, userData: var T): MatchResult =
  var ms = initMatchState()
  p.fn(ms, s, userData)

proc match*(p: Parser, s: Subject): MatchResult =
  var userData: bool # dummy if user does not provide a type
  p.match(s, userData)


# Match a subject stream

when false:
  import streams
  proc match*(p: Parser, s: Stream): MatchResult =
    var userData: bool # dummy if user does not provide a type
    var ms = initMatchState()
    var buf: array[3, char]
    while true:
      let l = s.readData(buf[0].addr, buf.len)
      echo p.fn(ms, toOpenArray(buf, 0, l-1), userData)
      if l == 0:
        break


# Match a file

when defined(windows) or defined(posix):
  import memfiles
  proc matchFile*[T](p: Parser, fname: string, userData: var T): MatchResult =
    var m = memfiles.open(fname)
    var a: ptr UncheckedArray[char] = cast[ptr UncheckedArray[char]](m.mem)
    var ms = initMatchState()
    result = p.fn(ms, toOpenArray(a, 0, m.size-1), userData)
    m.close()
  
  proc matchFile*(p: Parser, fname: string): MatchResult =
    var userData: bool # dummy if user does not provide a type
    matchFile(p, fname, userData)

# Return all plain string captures from the match result

proc captures*(mr: MatchResult): seq[string] =
  for cap in collectCaptures(mr.cs):
    result.add cap.s


# Return a tree with Json captures from the match result

proc capturesJson*(mr: MatchResult): JsonNode =
  collectCapturesJson(mr.cs)


# Return a tree with AST captures from the match result

proc capturesAST*(mr: MatchResult): ASTNode =
  collectCapturesAST(mr.cs)

proc `$`*(a: ASTNode): string =
  proc aux(a: ASTNode, s: var string, d: int=0) =
    s &= indent(a.id & " " & a.val, d) & "\n"
    for k in a.kids:
      aux(k, s, d+1)
  aux(a, result)


import npeg/lib/core

