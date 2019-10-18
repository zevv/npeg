
import macros
import strutils
import sequtils

import npeg/[common,stack]


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
    krak "NPeg: grammar too complex, (" & $p.len & " > " & $npegPattMaxLen & ").\n" &
         "If you think this is a mistake, increase the maximum size with -d:npegPattMaxLen=N"


# Checks if the passed patt matches an empty subject. This is done by executing
# the pattern as if it was passed an empty subject and see how it terminates.

proc matchesEmpty(patt: Patt): bool =
  var backStack = initStack[int]("backtrack", 8, 32)
  var ip: int
  while ip < patt.len:
    let i = patt[ip]
    case i.op
      of opChoice:
        push(backStack, ip+i.ipOffset)
        inc ip
      of opCommit:
        discard pop(backStack)
        ip += i.ipOffset
      of opJump: ip += i.callOffset
      of opCapOpen, opCapClose, opNop, opSpan, opPrecPush, opPrecPop: inc ip
      of opErr, opReturn, opCall: return false
      of opAny, opChr, opStr, opIstr, opSet, opBackRef, opFail:
        if i.failOffset != 0:
          ip += i.failOffset
        elif backStack.top > 0:
          ip = pop(backStack)
        else:
          return false
  return true


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
  let i = p[0]
  if i.failOffset == 0:
    case i.op
    of opStr, opIStr:
      result = (i.str.len, 1)
    of opChr, opAny, opSet:
      result = (1, 1)
    else:
      discard

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
    if matchesEmpty(p):
      krak "'*' repeat argument matches empty subject"
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

proc newPattAssoc*(p: Patt, prec: BiggestInt, assoc: Assoc): Patt =
  result.add Inst(op: opPrecPush, prec: prec.int, assoc: assoc)
  result.add p
  result.add Inst(op: opPrecPop)


### Others

proc `{}`*(p: Patt, n: BiggestInt): Patt =
  for i in 1..n:
    result.add p

proc `{}`*(p: Patt, range: HSlice[system.BiggestInt, system.BiggestInt]): Patt =
  result.add p{range.a}
  for i in range.a..range.b:
    result.add ?p


