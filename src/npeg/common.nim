
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
  npegOptimize* {.intDefine.} = 255
  npegDebug* = defined(npegDebug)
  npegTrace* = defined(npegTrace)
  npegExpand* = defined(npegExpand)
  npegGraph* = defined(npegGraph)
  npegProfile* = defined(npegProfile)

  # Various optimizations. These can be disabled for testing purposes
  # or when suspecting bugs in the optimization stages

  npegOptSets* = npegOptimize.testBit(0)
  npegOptHeadFail* = npegOptimize.testBit(1)
  npegOptCapShift* = npegOptimize.testBit(2)
  npegOptChoiceCommit* = npegOptimize.testBit(3)

type

  NPegException* = object of Exception
    matchLen*: int
    matchMax*: int
  
  CapFrameType* = enum cftOpen, cftClose
  
  CapKind* = enum
    ckStr,          # Plain string capture
    ckJString,      # JSON string capture
    ckJBool,        # JSON Bool capture
    ckJInt,         # JSON Int capture
    ckJFloat,       # JSON Float capture
    ckJArray,       # JSON Array
    ckJObject,      # JSON Object
    ckJFieldFixed,  # JSON Object field with fixed tag
    ckJFieldDynamic,# JSON Object field with dynamic tag
    ckAction,       # Action capture, executes Nim code at match time
    ckRef           # Reference
    ckAST,          # Abstract syntax tree capture
    ckClose,        # Closes capture

  CapFrame* = object
    cft*: CapFrameType # Capture frame type
    name*: string      # Capture name
    si*: int           # Subject index
    ck*: CapKind       # Capture kind
    sPushed*: string   # Pushed capture, overrides subject slice

  Ref* = object
    key*: string
    val*: string

  Subject* = openArray[char]

  Opcode* = enum
    opStr,          # Matching: Literal string 
    opIStr,         # Matching: Literal string, case insensitive
    opChr,          # Matching: Literal character
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
      of opStr, opIStr:
        str*: string
      of opChr:
        ch*: char
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
    name*: string
    pegRepr*: string

  Patt* = seq[Inst]

  TwoWayTable*[X,Y] = ref object
    x2y: Table[X, Y]
    y2x: Table[Y, X]

  Symtab* = TwoWayTable[string, int]

  Program* = object
    patt*: Patt
    symtab*: Symtab
    listing*: seq[string]

  Template* = ref object
    name*: string
    args*: seq[string]
    code*: NimNode

  Grammar* = ref object
    patts*: ref Table[string, Patt]
    templates*: ref Table[string, Template]

  ASTNode* = ref object
    id*: string
    val*: string
    kids*: seq[ASTNode]

#
# Two-way table
#

proc newTwoWayTable*[X,Y](): TwoWayTable[X,Y] =
  new result
  result.x2y = initTable[X, Y]()
  result.y2x = initTable[Y, X]()

proc add*[X,Y](s: TwoWayTable[X,Y], x: X, y: Y) =
  s.x2y[x] = y
  s.y2x[y] = x

proc contains*[X,Y](s: TwoWayTable[X,Y], y: Y): bool =
  return y in s.y2x

proc contains*[X,Y](s: TwoWayTable[X,Y], x: X): bool =
  return x in s.x2y

proc `[]`*[X,Y](s: TwoWayTable[X,Y], y: Y): X =
  return s.y2x[y]

proc `[]`*[X,Y](s: TwoWayTable[X,Y], x: X): Y =
  return s.x2y[x]


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
  echo "KRIK ", gCurErrorNode.repr
  krak gCurErrorNode, msg


#
# Misc helper functions
#

proc subStrCmp*(s: Subject, slen: int, si: int, s2: string): bool =
  if si > slen - s2.len:
    return false
  for i in 0..<s2.len:
    if s[si+i] != s2[i]:
      return false
  return true


proc subIStrCmp*(s: Subject, slen: int, si: int, s2: string): bool =
  if si > slen - s2.len:
    return false
  for i in 0..<s2.len:
    if s[si+i].toLowerAscii != s2[i].toLowerAscii:
      return false
  return true

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

#
# Some common operations for ASTNodes
#

proc `[]`*(a: ASTNode, id: string): ASTNode =
  for kid in a.kids:
    if kid.id == id:
      return kid

proc `[]`*(a: ASTNode, i: int): ASTNode =
  return a.kids[i]

iterator items*(a: ASTNode): ASTNode =
  for c in a.kids:
    yield c

proc `$`*(a: ASTNode): string =
  # Debug helper to convert an AST tree to representable string
  proc aux(a: ASTNode, s: var string, d: int=0) =
    s &= indent(a.id & " " & a.val, d) & "\n"
    for k in a.kids:
      aux(k, s, d+1)
  aux(a, result)


# Create a short and friendly text representation of a character set.

proc escapeChar*(c: char): string =
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
      result.add "'" & escapeChar(first.char) & "'..'" & escapeChar((c-1).char) & "',"
    inc c
  if result[result.len-1] == ',': result.setLen(result.len-1)
  result.add "}"

# Create a friendly version of the given string, escaping not-printables
# and no longer then `l`

proc dumpString*(s: Subject, o:int=0, l:int=1024): string =
  var i = o
  while i < s.len:
    let a = escapeChar s[i]
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
      if i.capAction != nil:
        args &= ": " & i.capAction.repr.indent(23)
    of opBackref:
      args = " " & i.refName
    of opPrecPush:
      args = " @" & $i.prec
    else:
      discard
  if i.failOffset != 0:
    args.add " " & $(ip+i.failOffset)
  result.add alignLeft(i.name, 15) &
             alignLeft(($i.op).toLowerAscii[2..^1] & args, 20) &
             " " & i.pegRepr

proc `$`*(program: Program): string =
  for ip, i in program.patt.pairs:
    if ip in program.symTab:
      result.add "\n" & program.symtab[ip] & ":\n"
    result.add align($ip, 4) & ": " & `$`(i, ip) & "\n"


proc slice*(s: Subject, iFrom, iTo: int): string =
  let len = iTo - iFrom
  result.setLen(len)
  for i in 0..<len:
    result[i] = s[i+iFrom]


proc `$`*(t: Template): string =
  return t.name & "(" & t.args.join(", ") & ") = " & t.code.repr

