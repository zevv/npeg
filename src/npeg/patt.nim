
import macros
import strutils
import sequtils

import npeg/common


# Create string representation of a pattern

when npegTrace:

  proc dump*(p: Patt, symtab: SymTab) =
    for n, i in p.pairs:
      if n in symTab:
        echo "\n" & symtab.get(n) & ":"
      var args: string
      case i.op:
        of opChr:
          args = " '" & escapeChar(i.ch) & "'"
        of opChoice, opCommit:
          args = " " & $(n+i.ipOffset)
        of opCall, opJump:
          args = " " & $(n+i.callOffset)
        of opCapOpen, opCapClose:
          args = " " & $i.capKind
          if i.capSiOffset != 0:
            args &= "(" & $i.capSiOffset & ")"
          if i.capAction != nil:
            args &= ": " & i.capAction.repr.indent(23)
        of opBackref:
          args = " " & i.refName
        else:
          discard
      if i.failOffset != 0:
        args.add " " & $(n+i.failOffset)
      echo align($n, 4) & ": " &
           alignLeft($i.name, 15) &
           alignLeft($i.op & args, 20) &
           " " & i.pegRepr


# Some tests on patterns

proc isSet(p: Patt): bool {.used.} =
  p.len == 1 and p[0].op == opSet


proc toSet(p: Patt, cs: var Charset): bool =
  when npegOptSets:
    if p.len == 1:
      let i = p[0]
      if i.op == opSet:
        cs = i.cs
        return true
      if i.op == opChr:
        cs = { i.ch }
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
    else:
      doAssert false


# Calculate how far captures or choices can be shifted into this pattern
# without consequences; this allows the pattern to fail before pushing to the
# backStack or capStack

proc canShift(p: Patt, enable: static[bool]): (int, int) =
  when enable:
    var siShift, ipShift: int
    for i in p:
      if i.failOffset != 0:
        break
      case i.op
      of opStr, opIStr:
        siShift.inc i.str.len
        ipShift.inc 1
      of opChr, opAny, opSet:
        siShift.inc 1
        ipShift.inc 1
      else: break
    result = (siShift, ipShift)

proc newPatt*(p: Patt, ck: CapKind, name = ""): Patt =
  let (siShift, ipShift) = p.canShift(npegOptCapShift)
  result.add p[0..<ipShift]
  result.add Inst(op: opCapOpen, capKind: ck, capSiOffset: -siShift, capName: name)
  result.add p[ipShift..^1]
  result.add Inst(op: opCapClose, capKind: ck)

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


# Add a choice/commit pair around pattern P, try to optimize head
# fails when possible

template addChoiceCommit(p: Patt, choiceOffset, commitOffset: int) =
  let (siShift, ipShift) = p.canShift(npegOptHeadFail)
  for n in 0..<ipShift:
    result.add p[n]
    result[result.high].failOffset = choiceOffset - n
  result.add Inst(op: opChoice, ipOffset: choiceOffset - ipShift, siOffset: -siShift)
  result.add p[ipShift..^1]
  result.add Inst(op: opCommit, ipOffset: commitOffset)


### Prefixes

proc `?`*(p: Patt): Patt =
  p.addChoiceCommit(p.len+2, 1)

proc `*`*(p: Patt): Patt =
  var cs: CharSet
  if p.toSet(cs):
    result.add Inst(op: opSpan, cs: cs)
  else:
    p.addChoiceCommit(p.len+2, -p.len-1)

proc `+`*(p: Patt): Patt =
  result.add p
  result.add *p

proc `>`*(p: Patt): Patt =
  return newPatt(p, ckStr)

proc `!`*(p: Patt): Patt =
  p.addChoiceCommit(p.len+3, 1)
  result.add Inst(op: opFail)

proc `&`*(p: Patt): Patt =
  result.add !(!p)

proc `@`*(p: Patt): Patt =
  p.addChoiceCommit(p.len+2, 3)
  result.add Inst(op: opAny)
  result.add Inst(op: opJump, callOffset: - p.len - 3)

### Infixes

proc `*`*(p1, p2: Patt): Patt =
  result.add p1
  result.add p2
  result.checkSanity


# choice() is generated from | operators by flattenChoice().
#
# Optimizations done here:
# - convert to union if all elements can be represented as a set
# - head fails: when possible, opChoice is shifted into a pattern to
#   allow the pattern to fail before emitting the opChoice

proc choice*(ps: openArray[Patt]): Patt =
  var csUnion: CharSet
  var allSets = true
  for p in ps:
    var cs: CharSet
    if p.toSet(cs):
      csUnion = csUnion + cs
    else:
      allSets = false
  if allSets:
    result.add Inst(op: opSet, cs: csUnion)
    return result

  var lenTot, ip: int
  lenTot = foldl(ps, a + b.len+2, 0)
  for i, p in ps:
    if i < ps.high:
      p.addChoiceCommit(p.len+2, lenTot-ip-p.len-3)
      ip += p.len + 2
    else:
      result.add p

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


