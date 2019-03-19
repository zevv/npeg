
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

  NPegException = object of Exception

  MatchResult* = object
    ok*: bool
    matchLen*: int
    captures*: seq[string]
    capturesJson*: JsonNode

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
    opCapOpen,      # Capture open
    opCapClose,     # Capture close
    opErr,          # Error handler

  CapKind = enum
    ckStr,          # Plain string capture
    ckInt,          # JSON Int capture
    ckFloat,        # JSON Float capture
    ckArray,        # JSON Array
    ckObject,       # JSON Object
    ckNamed,        # JSON Object named capture
    ckAction,       # Action capture, executes Nim code at match time
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
        callLabel: string
        callAddr: int
      of opSet, opSpan:
        cs: CharSet
      of opCapOpen, opCapClose:
        capKind: CapKind
        capAction: NimNode
        capName: string
      of opErr:
        msg: string
      of opFail, opReturn, opAny, opNop:
        discard

  Patt = seq[Inst]

  PattMap = Table[string, Patt]

  RetFrame* = int

  CapFrameType = enum cftOpen, cftClose

  CapFrame* = tuple
    cft: CapFrameType
    si: int
    ck: CapKind
    name: string

  Capture = object
    ck: CapKind
    si1, si2: int
    name: string
    len: int

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

template peek*[T](s: Stack[T]): T =
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


# Create a short and friendly text representation of a character set.

proc escapeChar(c: char): string =
  const escapes = { '\n': "\\n", '\r': "\\r", '\t': "\\t" }.toTable()
  if c in escapes:
    result = escapes[c]
  elif c >= ' ' and c <= '~':
    result = $c
  else:
    result = "\\x" & tohex(c.int, 2).toLowerAscii

proc dumpSet(cs: CharSet): string =
  result.add "{"
  var c = 0
  while c <= 255:
    let first = c
    while c <= 255 and c.char in cs:
      inc c
    if (c - 1 == first):
      result.add "'" & escapeChar(first.char) & "',"
    elif c - 1 > first:
      result.add "'" & escapeChar(first.char) & "'-'" & escapeChar((c-1).char) & "',"
    inc c
  if result[result.len-1] == ',': result.setLen(result.len-1)
  result.add "}"


# Create a friendly version of the given string, escaping not-printables
# and no longer then `l`

proc dumpString*(s: string, o:int=0, l:int=1024): string =
  var i = o
  while i < s.len:
    let a = escapeChar s[i]
    if result.len >= l-a.len:
      return
    result.add a
    inc i


# Create string representation of a pattern

proc `$`*(p: Patt): string =
  for n, i in p.pairs:
    var args: string
    case i.op:
      of opStr, opIStr:
        args = " " & dumpstring(i.str)
      of opSet, opSpan:
        args = " '" & dumpset(i.cs) & "'"
      of opChoice, opCommit, opPartCommit:
        args = " " & $(n+i.offset)
      of opCall, opJump:
        args = " " & i.callLabel & ":" & $i.callAddr
      of opErr:
        args = " " & i.msg
      of opCapOpen, opCapClose:
        args = " " & $i.capKind
      of opFail, opReturn, opNop, opAny:
        discard
    result &= align($n, 3) & ": " & alignLeft($i.op, 14) &
              alignLeft(args, 30) & "\n"

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

    template addOr(p1, p2: Patt) =
      add Inst(op: opChoice, offset: p1.len+2)
      add p1
      add Inst(op: opCommit, offset: p2.len+1)
      add p2

    template addCap(n: NimNode, ck: CapKind) =
      add Inst(op: opCapOpen, capKind: ck)
      add aux n
      add Inst(op: opCapClose, capKind: ck)

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
        if n[0].eqIdent "C":    addCap n[1], ckStr
        elif n[0].eqIdent "Ci": addCap n[1], ckInt
        elif n[0].eqIdent "Cf": addCap n[1], ckFloat
        elif n[0].eqIdent "Ca": addCap n[1], ckArray
        elif n[0].eqIdent "Co": addCap n[1], ckObject
        elif n[0].eqIdent "Cp":
          addCap n[1], ckAction
          result[result.high].capAction = n[2]
        elif n[0].eqIdent "Cn":
          let i = result.high
          addCap n[2], ckNamed
          result[i+1].capName = n[1].strVal
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
        elif n[0].eqIdent(">"):
          addCap n[1], ckStr
        else:
          krak n, "Unhandled prefix operator"
      of nnkInfix:
        let (p1, p2) = (aux n[1], aux n[2])
        if n[0].eqIdent("*"):
          add p1
          add p2
        elif n[0].eqIdent("-"):
          let (cs1, cs2) = (p1.toSet, p2.toSet)
          if cs1.isSome and cs2.isSome:
            add Inst(op: opSet, cs: cs1.get - cs2.get)
          else:
            addNot p2
            add p1
        elif n[0].eqIdent("|"):
          let (cs1, cs2) = (p1.toSet, p2.toSet)
          if cs1.isSome and cs2.isSome:
            add Inst(op: opSet, cs: cs1.get + cs2.get)
          else:
            addOr p1, p2
        else:
          krak n, "Unhandled infix operator"
      of nnkCurlyExpr:
        let p = aux(n[0])
        var min, max: BiggestInt
        if n[1].kind == nnkIntLit:
          min = n[1].intVal
        elif n[1].kind == nnkInfix and n[1][0].eqIdent(".."):
          (min, max) = (n[1][1].intVal, n[1][2].intVal)
        else:
          krak n, "syntax error"
        for i in 1..min: add p
        for i in min..max: addMaybe p
      of nnkIdent:
        let name = n.strVal
        if name in patts:
          add patts[name]
        else:
          add Inst(op: opCall, callLabel: n.strVal)
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
    if pname in result:
      error "Redefinition of rule '" & pname & "', which was defined in " &
            result[pname][0].n.lineInfo
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
      if i.op == opCall and i.callLabel notin symTab:
        if i.callLabel notin patts:
          error "Undefined pattern \"" & i.callLabel & "\"", i.n
        emit i.callLabel

  emit initial_name

  # Fixup call addresses and do tail call optimization

  for n, i in grammar.mpairs:
    if i.op == opCall:
      i.callAddr = symtab[i.callLabel]
    if i.op == opCall and grammar[n+1].op == opReturn:
      i.op = opJump

  return grammar


# Convert all closed CapFrames on the capture stack to a list
# of Captures

proc fixCaptures(capStack: var Stack[CapFrame], onlyOpen: bool): seq[Capture] =

  assert capStack.top > 0
  assert capStack.top mod 2 == 0
  assert capStack.peek.cft == cftCLose

  # Search the capStack for cftOpen matching the cftClose on top

  var iFrom = 0

  if onlyOpen:
    var i = capStack.top - 1
    var depth = 0
    while true:
      if capStack[i].cft == cftClose: inc depth else: dec depth
      if depth == 0: break
      dec i
    iFrom = i

  # Convert the closed frames to a seq[Capture]

  var stack: Stack[int]
  for i in iFrom..<capStack.top:
    let c = capStack[i]
    if c.cft == cftOpen:
      stack.push result.len
      result.add Capture(ck: c.ck, si1: c.si, name: c.name)
    else:
      let i2 = stack.pop()
      result[i2].si2 = c.si
      result[i2].len = result.len - i2 - 1
  assert stack.top == 0

  # Remove closed captures from the cap stack

  capStack.top = iFrom

  when false:
    for i, c in result:
      echo i, " ", c


proc collectCaptures(s: string, onlyOpen: bool, capStack: var Stack[CapFrame], res: var MatchResult) =

  let cs = fixCaptures(capStack, onlyOpen)

  proc aux(iStart, iEnd: int, parentNode: JsonNode, res: var MatchResult): JsonNode =

    var i = iStart
    while i <= iEnd:
      let cap = cs[i]

      case cap.ck:
        of ckStr:
          let str = s[cap.si1 ..< cap.si2]
          res.captures.add str
          result = newJString str
        of ckInt: result = newJInt parseInt(s[cap.si1 ..< cap.si2])
        of ckFloat: result = newJFloat parseFloat(s[cap.si1 ..< cap.si2])
        of ckArray: result = newJArray()
        of ckObject: result = newJObject()
        else: discard
      
      let nextParentNode = 
        if result != nil and result.kind in { Jarray, Jobject }: result
        else: parentNode

      if parentNode != nil and parentNode.kind == JArray:
        parentNode.add result

      inc i
      let childNode = aux(i, i+cap.len-1, nextParentNode, res)
      if parentNode != nil and cap.ck == ckNamed:
        parentNode[cap.name] = childNode
      i += cap.len 

  res.capturesJson = aux(0, cs.len-1, nil, res)


# Template for generating the parsing match proc.  A dummy 'ip' node is passed
# into this template to prevent its name from getting mangled so that the code
# in the `peg` macro can access it

template skel(cases: untyped, ip: NimNode, c: NimNode) =

  {.push hint[XDeclaredButNotUsed]: off.}

  let match = proc(s: string): MatchResult =

    var
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
      trace "str \"" & s2.dumpstring & "\""
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

    template opCapOpenFn(n: int, name2: string) =
      let ck = CapKind(n)
      trace "capopen " & $ck & " -> " & $si
      capStack.push (cft: cftOpen, si: si, ck: ck, name: name2)
      inc ip
    
    template opCapCloseFn(n: int, name2: string, actionCode: untyped) =
      let ck = CapKind(n)
      trace "capclose " & $ck & " -> " & $si
      capStack.push (cft: cftClose, si: si, ck: ck, name: name2)
      if ck == ckAction:
        var mr: MatchResult
        collectCaptures(s, true, capStack, mr)
        block:
          let c {.inject.} = mr.captures
          actionCode
      inc ip

    template opReturnFn() =
      trace "return"
      if retStack.top == 0:
        trace "done"
        result.ok = true
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
      raise newException(NpegException, "Parsing error at #" & $si & ": expected " & msg)

    while true:

      # These cases will be filled in by genCode() which uses this template
      # as the match lambda boilerplate:

      cases

      # Keep track of the highest string index we ever reached, this is a good
      # indication of the location of errors when parsing fails

      result.matchLen = max(result.matchLen, si)

    # When the parsing machine is done, close the capture stack and collect all
    # the captures in the match result

    if result.ok and capStack.top > 0:
      collectCaptures(s, false, capStack, result)

  {.pop.}

  match


# Convert the list of parser instructions into a Nim finite state machine

proc gencode(name: string, program: Patt): NimNode =

  let ipNode = ident("ip")
  let nopStmt = nnkStmtList.newTree(nnkDiscardStmt.newTree(newEmptyNode()))
  var cases = nnkCaseStmt.newTree(ipNode)

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
        call.add newStrLitNode(i.callLabel)
        call.add newIntLitNode(i.callAddr)
      of opCapOpen:
        call.add newIntLitNode(i.capKind.int)
        call.add newStrLitNode(i.capName)
      of opCapClose:
        call.add newIntLitNode(i.capKind.int)
        call.add newStrLitNode(i.capName)
        if i.capAction != nil:
          call.add nnkStmtList.newTree(i.capAction)
        else:
          call.add nopStmt
      of opErr:
        call.add newStrLitNode(i.msg)
      of opReturn, opAny, opNop, opFail:
        discard
    cases.add nnkOfBranch.newTree(newLit(n), call)

  cases.add nnkElse.newTree(parseStmt("opFailFn()"))

  result = getAst skel(cases, ipNode, ident "c")
  when false:
    echo result.repr


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

