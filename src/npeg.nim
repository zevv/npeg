
#
# Copyright (c) 2018 Ico Doornekamp
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
# - Roberto Ierusalimschy. A Text Pattern-Matching Tool based on Parsing Expression Grammars
# - Jos Craaijo. An efficient parsing machine for PEGs
#


import macros
import strutils
import options
import tables
import json

export escape

const npegTrace = defined(npegTrace)

type

  Opcode = enum
    opStr,          # Matching: Literal string or character
    opIStr,         # Matching: Literal string or character, case insensitive
    opSet,          # Matching: Character set and/or range
    opAny,          # Matching: Any character
    opNop,          # Matching: Always matches, consumes nothing
    opSpan          # Matching: Match a sequence of 0 or more character sets
    opChoice,       # Flow control: stores current position
    opCommit,       # Flow control: commit previous choice
    opPartCommit,   # Flow control: optimized commit/choice pair
    opCall,         # Flow control: call another rule
    opJump,         # Flow control: jump to target
    opReturn,       # Flow control: return from earlier call
    opFail,         # Fail: unwind stack until last frame
    opCap,          # Capture
    opErr,          # Error handler

  CapKind = enum
    ckNone,         # Empty slot
    ckStr,          # String capture
    ckArray,        # Array
    ckProc,         # Proc call capture
    ckClose,        # Closes capture

  CharSet = set[char]

  Inst = object
    n: NimNode
    case op: Opcode
      of opChoice, opCommit, opPartCommit:
        offset: int
      of opStr, opIStr:
        str: string
      of opCall, opJump:
        name: string
        address: int
      of opSet, opSpan:
        cs: CharSet
      of opCap:
        capKind: CapKind
        capCallback: NimNode
        fieldName: string
      of opErr:
        msg: string
      of opFail, opReturn, opAny, opNop:
        discard

  MatchResult = bool

  Patt = seq[Inst]

  PattMap = Table[string, Patt]

  RetFrame* = int

  CapFrame* = tuple
    si: int
    ck: CapKind

  Capture = object
    ck: CapKind
    open: bool
    si1, si2: int

  BackFrame* = tuple
    ip: int
    si: int
    rp: int
    cp: int

  Stack[T] = object
    top: int
    frames: seq[T]


# Stack generics

proc `$`*[T](s: Stack[T]): string =
  for i in 0..<s.top:
    result.add $i & ": " & $s.frames[i] & "\n"

template push*[T](s: var Stack[T], frame: T) =
  if s.top >= s.frames.len:
    s.frames.setLen if s.frames.len == 0: 8 else: s.frames.len * 2
  s.frames[s.top] = frame
  inc s.top

template pop*[T](s: var Stack[T]): T =
  assert s.top > 0
  dec s.top
  s.frames[s.top]

template peek*[T](s: var Stack[T]): T =
  assert s.top > 0
  s.frames[s.top-1]

template `[]`*[T](s: Stack[T], idx: int): T =
  assert idx < s.top
  s.frames[idx]

template update*[T](s: Stack[T], field: untyped, val: untyped) =
  assert s.top > 0
  s.frames[s.top-1].field = val


# Create a set containing all characters. This is used for optimizing
# set unions and differences with opAny

proc mkAnySet(): CharSet {.compileTime.} =
  for c in char.low..char.high:
    result.incl c
const anySet = mkAnySet()


# I don't know how to get rid of this on yet

proc nop*(s: string) = discard


# Create a short and friendly text representation of a character set.

proc dumpSet(cs: CharSet): string =
  proc esc(c: char): string =
    case c:
      of '\n': result = "'\\n'"
      of '\r': result = "'\\r'"
      of '\t': result = "'\\t'"
      elif c >= ' ' and c <= '~':
        result = "'" & $c & "'"
      else:
        result = "\\x" & tohex(c.int, 2).toLowerAscii
  result.add "{"
  var c = 0
  while c <= 255:
    let first = c
    while c <= 255 and c.char in cs:
      inc c
    if (c - 1 == first):
      result.add esc(first.char) & ","
    elif c - 1 > first:
      result.add esc(first.char) & "-" & esc((c-1).char) & ","
    inc c
  if result[result.len-1] == ',': result.setLen(result.len-1)
  result.add "}"


# Create a friendly version of the given string, escaping not-printables
# and no longer then `l`

proc dumpString*(s: string, o:int=0, l:int=1024): string =
  var i = o
  while i < s.len:
    if s[i] >= ' ' and s[i] <= 127.char:
      if result.len >= l-1:
        return
      result.add s[i]
    else:
      if result.len >= l-3:
        return
      result.add "\\x" & toHex(s[i].int, 2)
    inc i


# Create string representation of a pattern

proc `$`*(p: Patt): string =
  for n, i in p.pairs:
    result &= $n & ": " & $i.op
    case i.op:
      of opStr, opIStr:
        result &= " " & dumpstring(i.str)
      of opSet, opSpan:
        result &= " '" & dumpset(i.cs) & "'"
      of opChoice, opCommit, opPartCommit:
        result &= " " & $(n+i.offset)
      of opCall, opJump:
        result &= " " & i.name & ":" & $i.address
      of opErr:
        result &= " " & i.msg
      of opCap:
        result &= " " & $i.capKind
      of opFail, opReturn, opNop, opAny:
        discard
    result &= "\n"


# Some tests on patterns

proc isSet(p: Patt): bool =
  p.len == 1 and p[0].op == opSet


proc toSet(p: Patt): Option[CharSet] =
  if p.len == 1:
    let i = p[0]
    if i.op == opSet:
      return some i.cs
    if i.op == opStr and i.str.len == 1:
      return some { i.str[0] }
    if i.op == opIStr and i.str.len == 1:
      return some { toLowerAscii(i.str[0]), toUpperAscii(i.str[0]) }
    if i.op == opAny:
      return some anySet


# Recursively compile a peg pattern to a sequence of parser instructions

proc buildPatt(patts: PattMap, name: string, patt: NimNode): Patt =

  proc aux(n: NimNode): Patt =

    template add(p: Inst) =
      var pc = p
      pc.n = n
      result.add pc

    template add(p: Patt) =
      result.add p

    template addLoop(p: Patt) =
      if p.isSet:
        add Inst(op: opSpan, cs: p[0].cs)
      else:
        add Inst(op: opChoice, offset: p.len+2)
        add p
        add Inst(op: opPartCommit, offset: -p.len)

    template addMaybe(p: Patt) =
      add Inst(op: opChoice, offset: p.len + 2)
      add p
      add Inst(op: opCommit, offset: 1)

    template addNot(p: Patt) =
      add Inst(op: opChoice, offset: p.len + 3)
      add p
      add Inst(op: opCommit, offset: 1)
      add Inst(op: opFail)

    template addCap(n: NimNode, ck: CapKind) =
      add Inst(op: opCap, capKind: ck)
      add aux n
      add Inst(op: opCap, capKind: ckClose)

    template krak(n: NimNode, msg: string) =
      error "NPeg: " & msg & ": " & n.repr & "\n" & n.astGenRepr, n

    case n.kind:

      of nnKPar, nnkStmtList:
        add aux(n[0])
      of nnkIntLit:
        let c = n.intVal
        if c > 0:
          for i in 1..c:
            add Inst(op: opAny)
        else:
          add Inst(op: opNop)
      of nnkStrLit:
        add Inst(op: opStr, str: n.strVal)
      of nnkCharLit:
        add Inst(op: opStr, str: $n.intVal.char)
      of nnkCall:
        if n[0].eqIdent "C":
          addCap n[1], ckStr
        elif n[0].eqIdent "Ca":
          addCap n[1], ckArray
        #elif n[0].eqIdent "Co":
        #  addCap n[1], ckObject
        #elif n[0].eqIdent "Cf":
        #  addCap n[2], ckField
        #  result[result.high].fieldName = n[1].strVal
        #elif n[0].eqIdent "Cp":
        #  addCap n[2], ckProc
        #  result[result.high].capCallback = n[1]
        else:
          krak n, "Unhandled capture type"
      of nnkPrefix:
        let p = aux n[1]
        if n[0].eqIdent("?"):
          addMaybe p
        elif n[0].eqIdent("+"):
          add p
          addLoop p
        elif n[0].eqIdent("*"):
          addLoop p
        elif n[0].eqIdent("!"):
          addNot p
        else:
          krak n, "Unhandled prefix operator"
      of nnkInfix:
        let p1 = aux n[1]
        let p2 = aux n[2]
        if n[0].eqIdent("*"):
          add p1
          add p2
        elif n[0].eqIdent("-"):
          let cs1 = toSet(p1)
          let cs2 = toSet(p2)
          if cs1.isSome and cs2.isSome:
            add Inst(op: opSet, cs: cs1.get - cs2.get)
          else:
            addNot p2
            add p1
        elif n[0].eqIdent("|"):
          let cs1 = toSet(p1)
          let cs2 = toSet(p2)
          if cs1.isSome and cs2.isSome:
            add Inst(op: opSet, cs: cs1.get + cs2.get)
          else:
            add Inst(op: opChoice, offset: p1.len+2)
            add p1
            add Inst(op: opCommit, offset: p2.len+1)
            add p2
        else:
          krak n, "Unhandled infix operator"
      of nnkCurlyExpr:
        let p = aux(n[0])
        var min, max: BiggestInt
        if n[1].kind == nnkIntLit:
          min = n[1].intVal
        elif n[1].kind == nnkInfix and n[1][0].eqIdent(".."):
          min = n[1][1].intVal
          max = n[1][2].intVal
        else:
          krak n, "syntax error"
        for i in 1..min: add p
        for i in min..max: addMaybe p
      of nnkIdent:
        let name = n.strVal
        if name in patts:
          add patts[name]
        else:
          add Inst(op: opCall, name: n.strVal)
      of nnkCurly:
        var cs: CharSet
        for nc in n:
          if nc.kind == nnkCharLit:
            cs.incl nc.intVal.char
          elif nc.kind == nnkInfix:
            if nc[0].kind == nnkIdent and nc[0].eqIdent(".."):
              for c in nc[1].intVal..nc[2].intVal:
                cs.incl c.char
            else:
              krak n, "syntax error"
          else:
            krak n, "syntax error"
        if cs.card == 0:
          add Inst(op: opAny)
        else:
          add Inst(op: opSet, cs: cs)
      of nnkCallStrLit:
        if n[0].eqIdent("i"):
          add Inst(op: opIStr, str: n[1].strVal)
        elif n[0].eqIdent "E":
          add Inst(op: opErr, msg: n[1].strVal)
        else:
          krak n, "unhandled string prefix"
      else:
        krak n, "syntax error"

  result = aux(patt)


# Compile the PEG to a table of patterns

proc compile(ns: NimNode): PattMap =
  result = initTable[string, Patt]()

  for n in ns:
    n.expectKind nnkInfix
    n[0].expectKind nnkIdent
    n[1].expectKind nnkIdent
    if not n[0].eqIdent("<-"):
      error("Expected <-")
    let pname = n[1].strVal
    result[pname] = buildPatt(result, pname, n[2])


# Link all patterns into a grammar, which is itself again a valid pattern.
# Start with the initial rule, add all other non terminals and fixup opCall
# addresses

proc link(patts: PattMap, initial_name: string): Patt =

  if initial_name notin patts:
    error "inital pattern '" & initial_name & "' not found"

  var grammar: Patt
  var symTab = newTable[string, int]()

  # Recursively emit a pattern, and all patterns it calls which are
  # not yet emitted

  proc emit(name: string) =
    when npegTrace:
      echo "Emit ", name
    let patt = patts[name]
    symTab[name] = grammar.len
    grammar.add patt
    grammar.add Inst(op: opReturn)

    for i in patt:
      if i.op == opCall and i.name notin symTab:
        if i.name notin patts:
          error "Undefined pattern \"" & i.name & "\"", i.n
        emit i.name

  emit initial_name

  # Fixup call addresses and do tail call optimization

  for n, i in grammar.mpairs:
    if i.op == opCall:
      i.address = symtab[i.name]
    if i.op == opCall and grammar[n+1].op == opReturn:
      i.op = opJump

  return grammar


# Convert captures stack into list of matched open/close pairs

proc fixCaptures(capStack: Stack[CapFrame]): seq[Capture] =
  var stack: Stack[int]
  for i in 0..<capStack.top:
    let c = capStack[i]
    if c.ck != ckClose:
      stack.push result.len
      result.add Capture(ck: c.ck, si1: c.si, open: true)
    else:
      let i2 = stack.pop()
      result[i2].si2 = c.si
      result.add Capture(ck: result[i2].ck, open: false)
  assert stack.top == 0


proc collectCaptures(s: string, capStack: Stack[CapFrame], into: JsonNode) =

  let captures = fixCaptures(capStack)

  var stack: Stack[JsonNode]
  stack.push into

  for cap in captures:
    case cap.ck:
      of ckStr:
        if cap.open:
          stack.peek().add newJString s[cap.si1..<cap.si2]
      of ckArray:
        if cap.open:
          let a = newJArray()
          stack.peek().add a
          stack.push a
        else:
          discard stack.pop
      else:
        discard


# Template for generating the parsing match proc.  A dummy 'ip' node is passed
# into this template to prevent its name from getting mangled so that the code
# in the `peg` macro can access it

template skel(cases: untyped, ip: NimNode) =

  {.push hint[XDeclaredButNotUsed]: off.}

  let match = proc(s: string, into: JsonNode=nil): MatchResult =

    # Match state

    var
      complete: bool
      ip: int
      si: int
      retStack: Stack[RetFrame]
      capStack: Stack[CapFrame]
      backStack: Stack[BackFrame]

    # Debug trace. Slow and expensive

    proc doTrace(msg: string) =
      var l = align($ip, 3) &
           " | " & align($si, 3) &
           " |" & alignLeft(dumpstring(s, si, 24), 24) &
           "| " & alignLeft(msg, 30) &
           "| " & alignLeft(repeat("*", backStack.top), 20)
      if backStack.top > 0:
        l.add $backStack[backStack.top-1]
      echo l

    template trace(msg: string) =
      when npegTrace:
        doTrace(msg)

    # Helper procs

    proc subStrCmp(s: string, si: int, s2: string): bool =
      if si > s.len - s2.len:
        return false
      for i in 0..<s2.len:
        if s[si+i] != s2[i]:
          return false
      return true

    proc subIStrCmp(s: string, si: int, s2: string): bool =
      if si > s.len - s2.len:
        return false
      for i in 0..<s2.len:
        if s[si+i].toLowerAscii != s2[i].toLowerAscii:
          return false
      return true

    # State machine instruction handlers

    template opStrFn(s2: string) =
      trace "str " & s2.dumpstring
      if subStrCmp(s, si, s2):
        inc ip
        inc si, s2.len
      else:
        ip = -1

    template opIStrFn(s2: string) =
      trace "str " & s2.dumpstring
      if subIStrCmp(s, si, s2):
        inc ip
        inc si, s2.len
      else:
        ip = -1

    template opSetFn(cs: CharSet) =
      trace "set " & dumpset(cs)
      if si < s.len and s[si] in cs:
        inc ip
        inc si
      else:
        ip = -1

    template opSpanFn(cs: CharSet) =
      trace "span " & dumpset(cs)
      while si < s.len and s[si] in cs:
        inc si
      inc ip

    template opNopFn() =
      trace "nop"
      inc ip

    template opAnyFn() =
      trace "any"
      if si < s.len:
        inc ip
        inc si
      else:
        ip = -1

    template opChoiceFn(n: int) =
      trace "choice -> " & $n
      backStack.push (ip:n, si:si, rp:retStack.top, cp:capStack.top)
      inc ip

    template opCommitFn(n: int) =
      trace "commit -> " & $n
      discard backStack.pop()
      ip = n

    template opPartCommitFn(n: int) =
      trace "pcommit -> " & $n
      backStack.update(si, si)
      backStack.update(cp, capStack.top)
      ip = n

    template opCallFn(label: string, address: int) =
      trace "call -> " & label & ":" & $address
      retStack.push ip+1
      ip = address

    template opJumpFn(label: string, address: int) =
      trace "jump -> " & label & ":" & $address
      ip = address

    template opCapFn(n: int) =
      let ck = CapKind(n)
      trace "cap " & $ck & " -> " & $si
      capStack.push (si: si, ck: ck)
      inc ip

    template opReturnFn() =
      trace "return"
      if retStack.top == 0:
        trace "done"
        complete = true
        break
      ip = retStack.pop()

    template opFailFn() =

      if backStack.top == 0:
        trace "error"
        break

      (ip, si, retStack.top, capStack.top) = backStack.pop()

      trace "fail -> " & $ip

    template opErrFn(msg: string) =
      trace "err " & msg
      raise newException(OSError, "Parsing error at #" & $si & ": expected " & msg)

    while true:
      cases

    if complete and capStack.top > 0 and into != nil:
      collectCaptures(s, capStack, into)

    result = complete

  {.pop.}

  match


# Convert the list of parser instructions into a Nim finite state machine

proc gencode(name: string, program: Patt): NimNode =

  let ipNode = ident("ip")
  var cases = nnkCaseStmt.newTree(ipNode)
  cases.add nnkElse.newTree(parseStmt("opFailFn()"))

  for n, i in program.pairs:
    let call = nnkCall.newTree(ident($i.op & "Fn"))
    case i.op:
      of opStr, opIStr:
        call.add newStrLitNode(i.str)
      of opSet, opSpan:
        let setNode = nnkCurly.newTree()
        for c in i.cs: setNode.add newLit(c)
        call.add setNode
      of opChoice, opCommit, opPartCommit:
        call.add newIntLitNode(n + i.offset)
      of opCall, opJump:
        call.add newStrLitNode(i.name)
        call.add newIntLitNode(i.address)
      of opCap:
        call.add newIntLitNode(i.capKind.int)
      of opErr:
        call.add newStrLitNode(i.msg)
      of opReturn, opAny, opNop, opFail:
        discard
    cases.add nnkOfBranch.newTree(newLit(n), call)

  result = getAst skel(cases, ipNode)


# Convert a pattern to a Nim proc implementing the parser state machine

macro peg*(name: string, ns: untyped): untyped =
  let grammar = compile(ns)
  let patt = link(grammar, name.strVal)
  when npegTrace:
    echo patt
  gencode(name.strVal, patt)


macro patt*(ns: untyped): untyped =
  var symtab = initTable[string, Patt]()
  var patt = buildPatt(symtab, "p", ns)
  patt.add Inst(op: opReturn)
  when npegTrace:
    echo patt
  gencode("p", patt)

