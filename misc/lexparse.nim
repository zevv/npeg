import npeg, strutils, sequtils

type

  Token* = enum
    tInt
    tAdd
    cAddExpr

  Node = ref object
    case kind: Token
    of tInt:
      intval: int
    of tAdd:
      discard
    of cAddExpr:
      l, r: Node

  State = ref object
    tokens: seq[Node]
    stack: seq[Node]

# Npeg uses `==` to check if a subject matches a literal

proc `==`(n: Node, t: Token): bool = n.kind == t

proc `$`(n: Node): string =
  case n.kind
    of tInt: return $n.intVal
    of tAdd: return "+"
    of cAddExpr: return "(" & $n.l & " + " & $n.r & ")"

let lexer = peg(tokens, st: State):
  s      <- *Space
  tokens <- s * *(token * s)
  token  <- int | add
  int    <- +Digit:
    st.tokens.add Node(kind: tInt, intval: parseInt($0))
  add    <- '+':
    st.tokens.add Node(kind: tAdd)

let parser = peg(g, Node, st: State):
  g   <- int * *add * !1
  int <- [tInt]:
    st.stack.add $0
  add <- [tAdd] * int:
    st.stack.add Node(kind: cAddExpr, r: st.stack.pop, l: st.stack.pop)

var st = State()
doAssert lexer.match("1 + 2 + 3", st).ok
doAssert parser.match(st.tokens, st).ok
echo st.stack



