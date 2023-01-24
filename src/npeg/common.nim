
import strutils
import tables
import macros
import bitops


const

  # Some constants with "sane" defaults, configurable with compiler flags

  npegPattMaxLen* {.intdefine.} = 4096
  npegInlineMaxLen* {.intdefine.} = 30
  npegRetStackSize* {.intdefine.} = 1024
  npegBackStackSize* {.intdefine.} = 1024
  npegOptimize* {.intdefine.} = 255
  npegDebug* = defined(npegDebug)
  npegTrace* = defined(npegTrace)
  npegExpand* = defined(npegExpand)
  npegGraph* = defined(npegGraph)
  npegGcsafe* = defined(npegGcsafe)
  npegStacktrace* = defined(npegStacktrace)

  # Various optimizations. These can be disabled for testing purposes
  # or when suspecting bugs in the optimization stages

  npegOptSets* = npegOptimize.testBit(0)
  npegOptHeadFail* = npegOptimize.testBit(1)
  npegOptCapShift* = npegOptimize.testBit(2)
  npegOptChoiceCommit* = npegOptimize.testBit(3)

type

  NPegException* = object of CatchableError
    matchLen*: int
    matchMax*: int

  NPegParseError* = object of NPegException
  NPegStackOverflowError* = object of NPegException
  NPegUnknownBackrefError* = object of NPegException
  NPegCaptureOutOfRangeError* = object of NPegException

  CapFrameType* = enum cftOpen, cftClose

  CapKind* = enum
    ckVal,          # Value capture
    ckPushed,       # Pushed capture
    ckAction,       # Action capture, executes Nim code at match time
    ckRef           # Reference

  CapFrame*[S] = object
    cft*: CapFrameType # Capture frame type
    name*: string      # Capture name
    si*: int           # Subject index
    ck*: CapKind       # Capture kind
    when S is char:
      sPushed*: string # Pushed capture, overrides subject slice
    else:
      sPushed*: S      # Pushed capture, overrides subject slice

  Ref* = object
    key*: string
    val*: string

  Opcode* = enum
    opChr,          # Matching: Character
    opLit,          # Matching: Literal
    opSet,          # Matching: Character set and/or range
    opAny,          # Matching: Any character
    opNop,          # Matching: Always matches, consumes nothing
    opSpan          # Matching: Match a sequence of 0 or more character sets
    opChoice,       # Flow control: stores current position
    opCommit,       # Flow control: commit previous choice
    opCall,         # Flow control: call another rule
    opJump,         # Flow control: jump to target
    opReturn,       # Flow control: return from earlier call
    opFail,         # Fail: unwind stack until last frame
    opCapOpen,      # Capture open
    opCapClose,     # Capture close
    opBackref       # Back reference
    opErr,          # Error handler
    opPrecPush,     # Precedence stack push
    opPrecPop,      # Precedence stack pop

  CharSet* = set[char]

  Assoc* = enum assocLeft, assocRight

  Inst* = object
    case op*: Opcode
      of opChoice, opCommit:
        ipOffset*: int
        siOffset*: int
      of opChr:
        ch*: char
      of opLit:
        lit*: NimNode
      of opCall, opJump:
        callLabel*: string
        callOffset*: int
      of opSet, opSpan:
        cs*: CharSet
      of opCapOpen, opCapClose:
        capKind*: CapKind
        capAction*: NimNode
        capName*: string
        capSiOffset*: int
      of opErr:
        msg*: string
      of opFail, opReturn, opAny, opNop, opPrecPop:
        discard
      of opBackref:
        refName*: string
      of opPrecPush:
        prec*: int
        assoc*: Assoc
    failOffset*: int
    # Debug info
    name*: string
    nimNode*: NimNode
    indent*: int

  Patt* = seq[Inst]

  Symbol* = object
    ip*: int
    name*: string
    repr*: string
    lineInfo*: LineInfo

  SymTab* = object
    syms*: seq[Symbol]

  Rule* = object
    name*: string
    patt*: Patt
    repr*: string
    lineInfo*: LineInfo

  Program* = object
    patt*: Patt
    symTab*: SymTab

  Template* = ref object
    name*: string
    args*: seq[string]
    code*: NimNode

  Grammar* = ref object
    rules*: Table[string, Rule]
    templates*: Table[string, Template]

#
# SymTab implementation
#

proc add*(s: var SymTab, ip: int, name: string, repr: string = "", lineInfo: LineInfo = LineInfo()) =
  let symbol = Symbol(ip: ip, name: name, repr: repr, lineInfo: lineInfo)
  s.syms.add(symbol)

proc `[]`*(s: SymTab, ip: int): Symbol =
  for sym in s.syms:
    if ip >= sym.ip:
      result = sym

proc `[]`*(s: SymTab, name: string): Symbol =
  for sym in s.syms:
    if name == sym.name:
      return sym

proc contains*(s: SymTab, ip: int): bool =
  for sym in s.syms:
    if ip == sym.ip:
      return true

proc contains*(s: SymTab, name: string): bool =
  for sym in s.syms:
    if name == sym.name:
      return true

#
# Some glue to report parse errors without having to pass the original
# NimNode all the way down the call stack
#

var gCurErrorNode {.compileTime} = newEmptyNode()

proc setKrakNode*(n: NimNode) =
  gCurErrorNode.copyLineInfo(n)

template krak*(n: NimNode, msg: string) =
  error "NPeg: error at '" & n.repr & "': " & msg & "\n", n

template krak*(msg: string) =
  krak gCurErrorNode, msg


#
# Misc helper functions
#

proc subStrCmp*(s: openArray[char], slen: int, si: int, s2: string): bool =
  if si > slen - s2.len:
    return false
  for i in 0..<s2.len:
    if s[si+i] != s2[i]:
      return false
  return true


proc subIStrCmp*(s: openArray[char], slen: int, si: int, s2: string): bool =
  if si > slen - s2.len:
    return false
  for i in 0..<s2.len:
    if s[si+i].toLowerAscii != s2[i].toLowerAscii:
      return false
  return true


proc truncate*(s: string, len: int): string =
  result = s
  if result.len > len:
    result = result[0..len-1] & "..."

# This macro flattens AST trees of `|` operators into a single call to
# `choice()` with all arguments in one call. e.g, it will convert `A | B | C`
# into `call(A, B, C)`.

proc flattenChoice*(n: NimNode, nChoice: NimNode = nil): NimNode =
  proc addToChoice(n, nc: NimNode) =
    if n.kind == nnkInfix and n[0].eqIdent("|"):
      addToChoice(n[1], nc)
      addToChoice(n[2], nc)
    else:
      nc.add flattenChoice(n)
  if n.kind == nnkInfix and n[0].eqIdent("|"):
    result = nnkCall.newTree(ident "choice")
    addToChoice(n[1], result)
    addToChoice(n[2], result)
  else:
    result = copyNimNode(n)
    for nc in n:
      result.add flattenChoice(nc)


# Create a short and friendly text representation of a character set.

proc escapeChar*(c: char): string =
  const escapes = { '\n': "\\n", '\r': "\\r", '\t': "\\t" }.toTable()
  if c in escapes:
    result = escapes[c]
  elif c >= ' ' and c <= '~':
    result = $c
  else:
    result = "\\x" & toHex(c.int, 2).toLowerAscii

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
      result.add "'" & escapeChar(first.char) & "'..'" & escapeChar((c-1).char) & "',"
    inc c
  if result[result.len-1] == ',': result.setLen(result.len-1)
  result.add "}"

# Create a friendly version of the given string, escaping not-printables
# and no longer then `l`

proc dumpSubject*[S](s: openArray[S], o:int=0, l:int=1024): string =
  var i = o
  while i < s.len:
    when S is char:
      let a = escapeChar s[i]
    else:
      mixin repr
      let a = s[i].repr
    if result.len >= l-a.len:
      return
    result.add a
    inc i


proc `$`*(i: Inst, ip=0): string =
  var args: string
  case i.op:
    of opChr:
      args = " '" & escapeChar(i.ch) & "'"
    of opChoice, opCommit:
      args = " " & $(ip+i.ipOffset)
    of opCall, opJump:
      args = " " & $(ip+i.callOffset)
    of opCapOpen, opCapClose:
      args = " " & $i.capKind
      if i.capSiOffset != 0:
        args &= "(" & $i.capSiOffset & ")"
    of opBackref:
      args = " " & i.refName
    of opPrecPush:
      args = " @" & $i.prec
    else:
      discard
  if i.failOffset != 0:
    args.add " " & $(ip+i.failOffset)
  let tmp = if i.nimNode != nil: i.nimNode.repr.truncate(30) else: ""
  result.add alignLeft(i.name, 15) &
             alignLeft(repeat(" ", i.indent) & ($i.op).toLowerAscii[2..^1] & args, 25) & " " & tmp

proc `$`*(program: Program): string =
  for ip, i in program.patt.pairs:
    if ip in program.symTab:
      result.add "\n" & program.symTab[ip].repr & "\n"
    result.add align($ip, 4) & ": " & `$`(i, ip) & "\n"


proc slice*(s: openArray[char], iFrom, iTo: int): string =
  let len = iTo - iFrom
  result.setLen(len)
  for i in 0..<len:
    result[i] = s[i+iFrom]

proc slice*[S](s: openArray[S], iFrom, iTo: int): S =
  result = s[iFrom]

proc `$`*(t: Template): string =
  return t.name & "(" & t.args.join(", ") & ") = " & t.code.repr

