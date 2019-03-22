
import capture
import macros
import strutils
import options
import tables
import json

import npeg/common

type

  Opcode* = enum
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

  CharSet* = set[char]

  Inst* = object
    case op*: Opcode
      of opChoice, opCommit, opPartCommit:
        offset*: int
      of opStr, opIStr:
        str*: string
      of opCall, opJump:
        callLabel*: string
        callAddr*: int
      of opSet, opSpan:
        cs*: CharSet
      of opCapOpen, opCapClose:
        capKind*: CapKind
        capAction*: NimNode
        capName*: string
      of opErr:
        msg*: string
      of opFail, opReturn, opAny, opNop:
        discard
    when npegTrace:
      name*: string

  Patt* = seq[Inst]


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

proc dumpSet*(cs: CharSet): string =
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

proc dump*(p: Patt, symtab: SymTab = nil) =
  for n, i in p.pairs:
    if symTab != nil and n in symTab:
      echo symtab.get(n) & ":"
    var args: string
    case i.op:
      of opStr, opIStr:
        args = " " & dumpString(i.str)
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
    var l: string
    l.add align($n, 3) & ": " 
    when npegTrace:
      l.add alignLeft($i.name, 15)
    l.add $i.op & " " & args
    echo l

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

### Atoms

proc newStrLitPatt*(s: string): Patt =
  result.add Inst(op: opStr, str: s)

proc newIStrLitPatt*(s: string): Patt =
  result.add Inst(op: opIStr, str: s)

proc newCapPatt*(p: Patt, ck: CapKind): Patt =
  result.add Inst(op: opCapOpen, capKind: ck)
  result.add p
  result.add Inst(op: opCapClose, capKind: ck)

proc newCallPatt*(label: string): Patt =
  result.add Inst(op: opCall, callLabel: label)

proc newIntLitPatt*(n: BiggestInt): Patt =
  if n > 0:
    for i in 1..n:
      result.add Inst(op: opAny)
  else:
    result.add Inst(op: opNop)

proc newSetPatt*(cs: CharSet): Patt =
  result.add Inst(op: opSet, cs: cs)

proc newReturnPatt*(): Patt =
  result.add Inst(op: opReturn)

### Prefixes

proc `?`*(p: Patt): Patt =
  result.add Inst(op: opChoice, offset: p.len + 2)
  result.add p
  result.add Inst(op: opCommit, offset: 1)

proc `*`*(p: Patt): Patt =
  if p.isSet:
    result.add Inst(op: opSpan, cs: p[0].cs)
  else:
    result.add Inst(op: opChoice, offset: p.len+2)
    result.add p
    result.add Inst(op: opPartCommit, offset: -p.len)

proc `+`*(p: Patt): Patt =
  result.add p
  result.add *p

proc `>`*(p: Patt): Patt =
  return newCapPatt(p, ckStr)

proc `!`*(p: Patt): Patt =
  result.add Inst(op: opChoice, offset: p.len + 3)
  result.add p
  result.add Inst(op: opCommit, offset: 1)
  result.add Inst(op: opFail)

### Infixes

proc `*`*(p1, p2: Patt): Patt =
  result.add p1
  result.add p2

proc `|`*(p1, p2: Patt): Patt =
  let (cs1, cs2) = (p1.toSet, p2.toSet)
  if cs1.isSome and cs2.isSome:
    result.add Inst(op: opSet, cs: cs1.get + cs2.get)
  else:
    result.add Inst(op: opChoice, offset: p1.len+2)
    result.add p1
    result.add Inst(op: opCommit, offset: p2.len+1)
    result.add p2

proc `-`*(p1, p2: Patt): Patt =
  let (cs1, cs2) = (p1.toSet, p2.toSet)
  if cs1.isSome and cs2.isSome:
    result.add Inst(op: opSet, cs: cs1.get - cs2.get)
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


