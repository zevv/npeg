import npeg
import strutils

# Rod AST node types

type
  NodeKind* = enum
    nkEmpty
    nkScript, nkBlock
    nkBool, nkNumber, nkString, nkIdent
    nkPrefix, nkInfix, nkDot, nkIndex
    nkVar, nkLet
    nkIf, nkWhile, nkFor
    nkBreak, nkContinue
    nkCall
    nkGeneric
    nkObject, nkObjFields, nkObjConstr
  Node* = ref object
    ln*, col*: int
    file*: string
    case kind*: NodeKind
    of nkEmpty: discard
    of nkBool:
      boolVal*: bool
    of nkNumber:
      numberVal*: float
    of nkString:
      stringVal*: string
    of nkIdent:
      ident*: string
    else:
      children*: seq[Node]

type
  ParseStack = seq[Node]


# Pretty printing

proc `$`*(node: Node, showLineInfo = false): string =
  const LeafNodes = { nkEmpty, nkBool, nkNumber, nkString, nkIdent, nkPrefix, nkInfix }
  case node.kind
  of nkEmpty: result = "<empty>"
  of nkBool: result = $node.boolVal
  of nkNumber: result = $node.numberVal
  of nkString: result = escape(node.stringVal)
  of nkIdent: result = node.ident
  else:
    result = (if showLineInfo: $node.ln & ":" & $node.col & " " else: "") &
             "(" & (case node.kind
                    of nkPrefix, nkInfix: ""
                    else: $node.kind & " ")
    for i, child in node.children:
      if child.kind notin LeafNodes and node.children.len > 1:
        result.add("\n")
        result.add(indent(`$`(child, showLineInfo), 2))
      else:
        if i > 0:
          result.add(" ")
        result.add(`$`(child, showLineInfo))
    result.add(")")

proc `$`*(ps: ParseStack): string =
  for i, n in ps:
    result &= $i & ":\n" & $n & "\n"
  result &= "\n"



proc addToParent(ps: var ParseStack, ns: varargs[Node]) =
  ps[ps.high].children.add ns

proc swap(ps: var ParseStack) =
  ps.add ps[ps.high-1]
  ps.delete ps.high-2

let p = peg(rod, ps: ParseStack):

  S <- *Space

  # Basic tokens

  tokColon    <- ":" * S
  tokEquals   <- "=" * S
  tokComma    <- "," * S
  tokPlus     <- "+" * S
  tokMinus    <- "-" * S
  tokMul      <- "*" * S
  tokDiv      <- "/" * S
  tokParOpen  <- "(" * S
  tokParClose <- ")" * S
  tokCurOpen  <- "{" * S
  tokCurClose <- "}" * S
  tokVar      <- "var" * S
  tokLet      <- "let" * S
  tokIf       <- "if" * S
  tokElif     <- "elif" * S
  tokElse     <- "else" * S
  tokWhile    <- "while" * S
  tokObject   <- "object" * S
  
  keyWords    <- "var" | "let" | "if" | "elif" | "else" | "while" | "object"

  # Atoms

  tokNumber   <- >+Digit * S:
    ps.add Node(kind: nkNumber, numberVal: parseFloat($1))

  tokType     <- Alpha * *Alnum * S
  
  tokBool     <- >("true" | "false") * S:
    ps.add Node(kind: nkBool, boolval: $1 == "true")

  tokIdent    <- >((Alpha * *Alnum) - keyWords) * S:
    ps.add Node(kind: nkIdent, ident: $1)

  # Block

  blockOpen   <- tokCurOpen:
    ps.add Node(kind: nkBlock)

  blockStmt   <- stmt:
    ps.addToParent ps.pop()

  blockSec    <- blockOpen * *blockStmt * tokCurClose

  # Var section

  varOpen     <- (tokVar | tokLet):
    ps.add Node(kind: nkVar)
  
  varDef      <- tokIdent * ?(tokColon * tokType) * ?(tokEquals * exprSec):
    ps.swap()
    ps.addToParent Node(kind: nkVar,
                        children: @[Node(kind: nkIdent, ident: "="), ps.pop(), ps.pop()])

  varSec      <- varOpen * +varDef * *(tokComma * varDef):
    ps.add ps.pop()

  # While statement

  whileSec    <- tokWhile * exprSec * blockSec:
    ps.swap()
    ps.add Node(kind: nkWhile, children: @[ps.pop(), ps.pop()])

  # If expressions

  ifOpen      <- tokIf * exprSec * blockSec:
    let (nBlock, nExpr) = (ps.pop(), ps.pop())
    ps.add Node(kind: nkIf, children: @[nExpr, nBlock])

  ifElif      <- (tokElif * exprSec * blockSec):
    ps.swap()
    ps.addtoParent ps.pop(), ps.pop()

  ifElse      <- ?(tokElse * blockSec):
    ps.addToParent ps.pop()

  ifExpr      <- ifOpen * *ifElif * ?ifElse

  # Object

  objectSec   <- tokObject * tokIdent * tokCurOpen * objFields * tokCurClose

  objFields   <- tokIdent * *(tokComma * tokIdent) * tokColon * tokType

  stmt        <- blockSec | varSec | objectSec | whileSec | exprSec

  rod         <- S * +stmt * !1

  # Expressions: Pratt parser

  exprSec <- exp

  exp <- S * prefix * *infix

  prefix <- ifExpr | tokBool | tokNumber | parenExp | uniMinus | tokIdent
  uniMinus <- >'-' * exp
  parenExp <- ( tokParOpen * exp * tokParClose ) ^ 0

  infix <- >("not" | "->" | "$")                     * exp ^ 1 |
           >("=")                                    * exp ^ 2 |
           >("or" | "xor")                           * exp ^ 3 |
           >("and")                                  * exp ^ 4 |
           >("==" | "<=" | "<" | ">=" | ">" | "!=" | 
             "in" | "notin" | "is" | "isnot" | "of") * exp ^ 5 |
           >(".." | "..<")                           * exp ^ 6 |
           >("&")                                    * exp ^ 7 |
           >("+" | "-")                              * exp ^ 8 |
           >("*" | "/" | "%")                        * exp ^ 9 |
           >("div" | "mod" | "shl" | "shr")          * exp ^ 10 |
           >("^")                                    * exp ^^ 11:

    let (f2, f1) = (ps.pop(), ps.pop())
    ps.add Node(kind: nkInfix, children:
                @[Node(kind: nkIdent, ident: $1), f1, f2])


proc compile(source:string) =
  var ps: ParseStack
  echo "---------------"
  echo source
  if p.match(source, ps).ok:
    echo "---------------"
    let n = Node(kind: nkBlock, children: ps)
    echo n

when false:
  compile """
    if a > 3 {
      var w = 42
    }
  """

when false:
    compile("""
    var
      a = 2 + 2,
      b = 2 + a
    """)
  
when true:
    compile("""
    { var a = 10
      { var a = a } }
    { var a = 12
      a = a + 3 }
    """)
  
when false:
    compile("""
    let x = true
    if x {
      var x = 2
    } 
    """)

when false:
    compile("""
    let x = true
    if x {
      var x = 2
    } elif false {
      var y = 3
    } elif false {
      var z = 4
    } else {
      var w = 5
    }
    """)

when false:
    compile("""
    let x = if true { 2 }
            else { 4 }
    """)
 
when false:
    compile("""
    let x = true
    while x {
      let y = 1
    }
    """)

when false:
    compile("""
    while true {
      let y = 1
    }
    """)

when false:
    compile("""
    while false {
      let y = 1
    }
    """)

when false:
    compile("""
    var
      x = 0,
      stop = false
    while x {
    }
    """)
