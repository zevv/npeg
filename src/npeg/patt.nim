
import macros
import strutils

import npeg/common


# Create string representation of a pattern

proc dump*(p: Patt, symtab: SymTab): seq[string] =
  for n, i in p.pairs:
    var args: string
    case i.op:
      of opChr, opIChr:
        args = " '" & escapeChar(i.ch) & "'"
      of opChoice, opCommit, opPartCommit:
        args = " " & $(n+i.offset)
      of opCall, opJump:
        args = " " & $(n+i.callOffset)
      of opCapOpen, opCapClose:
        args = " " & $i.capKind
        if i.capAction != nil:
          args &= ": " & i.capAction.repr.indent(23)
      of opBackref:
        args = " " & i.refName
      else:
        discard
    result.add align($n, 4) & ": " &
         alignLeft($i.name, 16) &
         alignLeft($i.op & args, 20) &
         " " & i.pegRepr


# Some tests on patterns

proc isSet(p: Patt): bool {.used.} =
  p.len == 1 and p[0].op == opSet


proc toSet(p: Patt, cs: var Charset): bool =
  if p.len == 1:
    let i = p[0]
    if i.op == opSet:
      cs = i.cs
      return true
    if i.op == opChr:
      cs = { i.ch }
      return true
    if i.op == opIChr:
      cs = { toLowerAscii(i.ch), toUpperAscii(i.ch) }
      return true
    if i.op == opStr and i.str.len == 1:
      cs = { i.str[0] }
      return true
    if i.op == opIStr and i.str.len == 1:
      cs = { toLowerAscii(i.str[0]), toUpperAscii(i.str[0]) }
      return true
    if i.op == opAny:
      cs = {low(char)..high(char)}
      return true


proc checkSanity(p: Patt) =
  if p.len >= npegPattMaxLen:
    error "NPeg: grammar too complex, (" & $p.len & " > " & $npegPattMaxLen & ").\n" &
          "If you think this is a mistake, increase the maximum size with -d:npegPattMaxLen=N"

### Atoms

proc newPatt*(s: string, op: Opcode): Patt =
  case op:
    of opStr:
      result.add Inst(op: opStr, str: s)
    of opIStr:
      result.add Inst(op: opIStr, str: s)
    of opChr:
      for ch in s:
        result.add Inst(op: opChr, ch: ch)
    of opIChr:
      for ch in s:
        result.add Inst(op: opIChr, ch: ch.toLowerAscii)
    else:
      doAssert false

proc newPatt*(p: Patt, ck: CapKind): Patt =
  result.add Inst(op: opCapOpen, capKind: ck)
  result.add p
  result.add Inst(op: opCapClose, capKind: ck)

proc newPatt*(p: Patt, ck: CapKind, name: string): Patt =
  result = newPatt(p, ck)
  result[0].capName = name

proc newCallPatt*(label: string): Patt =
  result.add Inst(op: opCall, callLabel: label)

proc newPatt*(n: BiggestInt): Patt =
  if n > 0:
    for i in 1..n:
      result.add Inst(op: opAny)
  else:
    result.add Inst(op: opNop)

proc newPatt*(cs: CharSet): Patt =
  result.add Inst(op: opSet, cs: cs)

proc newBackrefPatt*(refName: string): Patt =
  result.add Inst(op: opBackref, refName: refName)

proc newReturnPatt*(): Patt =
  result.add Inst(op: opReturn)

proc newErrorPatt*(msg: string): Patt =
  result.add Inst(op: opErr, msg: msg)

### Prefixes

proc `?`*(p: Patt): Patt =
  result.add Inst(op: opChoice, offset: p.len + 2)
  result.add p
  result.add Inst(op: opCommit, offset: 1)

proc `*`*(p: Patt): Patt =
  var cs: CharSet
  if p.toSet(cs):
    result.add Inst(op: opSpan, cs: cs)
  else:
    result.add Inst(op: opChoice, offset: p.len+2)
    result.add p
    result.add Inst(op: opPartCommit, offset: -p.len)

proc `+`*(p: Patt): Patt =
  result.add p
  result.add *p

proc `>`*(p: Patt): Patt =
  return newPatt(p, ckStr)

proc `!`*(p: Patt): Patt =
  result.add Inst(op: opChoice, offset: p.len + 3)
  result.add p
  result.add Inst(op: opCommit, offset: 1)
  result.add Inst(op: opFail)

proc `&`*(p: Patt): Patt =
  result.add !(!p)

proc `@`*(p: Patt): Patt =
  result.add Inst(op: opChoice, offset: p.len + 2)
  result.add p
  result.add Inst(op: opCommit, offset: 3)
  result.add Inst(op: opAny)
  result.add Inst(op: opJump, callOffset: - p.len - 3)

### Infixes

proc `*`*(p1, p2: Patt): Patt =
  result.add p1
  result.add p2
  result.checkSanity

proc `|`*(p1, p2: Patt): Patt =
  var cs1, cs2: Charset
  if p1.toSet(cs1) and p2.toSet(cs2):
    result.add Inst(op: opSet, cs: cs1 + cs2)
  else:
    # Optimization: detect if P1 is already an ordered choice, and rewrite the
    # offsets in the choice and commits instructions, then add the new choice
    # P2 to the end. The naive implementation would generate inefficient code
    # because the | terms are added left-associative.
    var p3 = p1
    var ip = 0
    while p3[ip].op == opChoice:
      let ipCommit = p3[ip].offset + ip - 1
      if p3[ipCommit].op == opCommit and p3[ipCommit].offset + ipCommit == p1.len:
        p3[ipCommit].offset += p2.len + 2
        ip = ipCommit + 1
      else:
        break
    p3.setlen ip
    p3.add Inst(op: opChoice, offset: p1.high - ip + 3)
    p3.add p1[ip..p1.high]
    p3.add Inst(op: opCommit, offset: p2.len + 1)
    p3.add p2
    result = p3
  result.checkSanity

proc `-`*(p1, p2: Patt): Patt =
  var cs1, cs2: Charset
  if p1.toSet(cs1) and p2.toSet(cs2):
    result.add Inst(op: opSet, cs: cs1 - cs2)
  else:
    result.add !p2
    result.add p1

### Others

proc `{}`*(p: Patt, n: BiggestInt): Patt =
  for i in 1..n:
    result.add p

proc `{}`*(p: Patt, range: HSlice[system.BiggestInt, system.BiggestInt]): Patt =
  result.add p{range.a}
  for i in range.a..range.b:
    result.add ?p


