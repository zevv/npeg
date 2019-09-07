
import macros, unicode, strutils, tables
import npeg/[patt,grammar,common]


type

  Sym = object
    x, y: int
    r: Rune

  Node = ref object
    w, y0, y1: int
    syms: seq[Sym]
    kids: seq[Kid]

  Kid = object
    dx, dy: int
    n: Node

#
# Renders a node to text output
#

proc `$`*(n: Node): string =
  if n == nil:
    return ""
  let h = n.y1 - n.y0 + 1
  let y0 = n.y0
  var l: seq[Rune]
  var ls: seq[seq[Rune]]
  for x in 0..<n.w: l.add ' '.Rune
  for y in 0..<h: ls.add l
               
  proc render(n: Node, x, y: int) =
    for k in n.kids:
      render(k.n, x + k.dx, y + k.dy)
    for s in n.syms:
      let sx = x+s.x
      let sy = y+s.y - y0
      ls[sy][sx] = s.r
  render(n, 0, 0)
  result = ls.join("\n")


proc poke(n: Node, x, y: int, r: Rune) =
  n.syms.add Sym(x: x, y: y, r: r)

proc poke(n: Node, x, y: int, s: string) =
  n.poke(x, y, s.runeAt(0))

proc pad(n: Node, left, right: int): Node = 
  result = Node(w: n.w + left + right, y0: n.y0, y1: n.y1)
  for x in 0..<left:
    result.poke(x, 0, "─")
  for x in n.w+left..<result.w:
    result.poke(x, 0, "─")
  result.kids.add Kid(n: n, dx: left, dy: 0)

proc wrap*(n: Node, name: string): Node =
  let namer = (name & " ").toRunes()
  let nl = namer.len()
  result = Node(w: n.w+4+nl, y0: n.y0, y1: n.y1)
  result.kids.add Kid(n: n, dx: 2+nl)
  result.poke(nl+0, 0, "o")
  result.poke(nl+1, 0, "─")
  result.poke(result.w-2, 0, "─")
  result.poke(result.w-1, 0, "o")
  for i in 0..<nl:
    result.poke(i, 0, namer[i])

proc newNode(): Node =
  result = Node()

proc newNode(s: string): Node =
  let rs = s.toRunes()
  let n = Node(w: rs.len)
  for x in 0..<rs.len:
    n.poke(x, 0, rs[x])
  result = n.pad(1, 1)

proc newNode(n: Node, ck: CapKind, s: string=""): Node =
  return n

proc `*`(n1, n2: Node): Node =
  result = Node(w: n1.w + n2.w, y0: min(n1.y0, n2.y0), y1: max(n1.y1, n2.y1))
  result.kids.add Kid(n: n1, dx: 0)
  result.kids.add Kid(n: n2, dx: n1.w)

proc `?`(n: Node): Node =
  result = Node(w: n.w+2, y0: -1 + n.y0, y1: n.y1)
  result.kids.add Kid(n: n.pad(1, 1))
  let (y1, y2) = (-1 + n.y0, 0)
  let (x1, x2) = (0, n.w+1)
  result.poke(x1, y1, "╭")
  result.poke(x1, y2, "┴")
  result.poke(x2, y1, "╮")
  result.poke(x2, y2, "┴")
  for x in x1+1..x2-1:
    result.poke(x, y1, "─")
  for y in y1+1..y2-1:
    result.poke(x1, y, "│")
    result.poke(x2, y, "│")
  result.poke((x1+x2)/%2, y1, "»")

proc `+`(n: Node): Node =
  result = Node(w: n.w+2, y0: n.y0, y1: n.y1+1)
  result.kids.add Kid(n: n.pad(1, 1), dy:  0)
  let (y1, y2) = (0, n.y1+1)
  let (x1, x2) = (0, n.w+1)
  result.poke(x1, y1, "┬")
  result.poke(x1, y2, "╰")
  result.poke(x2, y1, "┬")
  result.poke(x2, y2, "╯")
  for x in x1+1..x2-1:
    result.poke(x, y2, "─")
  for y in y1+1..y2-1:
    result.poke(x1, y, "│")
    result.poke(x2, y, "│")
  result.poke((x1+x2)/%2, y2, "«")

proc `-`*(p1, p2: Node): Node =
  return p1

proc `*`(n: Node): Node = ? + n

proc choice(ns: varArgs[Node]): Node =
  var wmax = 0
  for n in ns:
    wmax = max(wmax, n.w)
  var y0 = ns[0].y0
  var y1 = ns[1].y1
  for n in ns:
    inc y1, n.y1 - n.y0 + 1
  var dys = @[0]
  var dy = 0
  for i in 0..<ns.len-1:
    inc dy, ns[i].y1 - ns[i+1].y0 + 1
    dys.add dy
  result = Node(w: wmax+4, y0: y0, y1: y1-1)
  let x0 = 1
  let x1 = wmax+2
  result.poke(0, 0, "─")
  result.poke(result.w-1, 0, "─")
  for i in 0..<ns.len:
    let n = ns[i]
    result.kids.add Kid(n: n.pad(0, wmax-n.w), dx: 2, dy: dys[i])
  for y in 1..<dys[dys.high]:
    result.poke(x0, y, "│")
    result.poke(x1, y, "│")
  result.poke(x0, 0, "┬")
  result.poke(x1, 0, "┬")
  for i in 0..<ns.len-1:
    if i > 0:
      result.poke(x0, dys[i], "├")
      result.poke(x1, dys[i], "┤")
  result.poke(x0, dys[dys.high], "╰")
  result.poke(x1, dys[dys.high], "╯")

proc `{}`*(p: Node, n: BiggestInt): Node =
  result = p
  for i in 1..n:
    result = result * p

proc `{}`*(p: Node, range: HSlice[system.BiggestInt, system.BiggestInt]): Node =
  result = p{range.a}
  for i in range.a..range.b:
    result = result * ?p


# This macro flattens AST trees of `|` operators into a single call to
# `choice()` with all arguments in one call. e.g, it will convert `A | B | C`
# into `call(A, B, C)`.

proc flattenChoice(n: NimNode, nChoice: NimNode = nil): NimNode

proc addToChoice(n, nc: NimNode) =
  if n.kind == nnkInfix and n[0].eqIdent("|"):
    addToChoice(n[1], nc)
    addToChoice(n[2], nc)
  else:
    nc.add flattenChoice(n)

proc flattenChoice(n: NimNode, nChoice: NimNode = nil): NimNode =
  result = copyNimNode(n)
  if n.kind == nnkInfix and n[0].eqIdent("|"):
    result = nnkCall.newTree(ident "choice")
    addToChoice(n[1], result)
    addToChoice(n[2], result)
  else:
    for nc in n:
      result.add flattenChoice(nc)


# This is a simplified parser based on parsePatt(), but lacking any error
# checking. This will always run after parsePatt(), so any errors would already
# have been caught tehere

proc parseRailRoad*(nn: NimNode, grammar: Grammar): Node =

  proc aux(n: NimNode): Node =

    proc applyTemplate(name: string, arg: NimNode): NimNode =
      let t = if name in grammar.templates:
        grammar.templates[name]
      else:
        libImportTemplate(name)
      if t != nil:
        proc aux(n: NimNode): NimNode =
          if n.kind == nnkIdent and n.strVal in t.args:
            result = arg[ find(t.args, n.strVal)+1 ]
          else:
            result = copyNimNode(n)
            for nc in n:
              result.add aux(nc)
        result = aux(t.code)

    case n.kind:

      of nnKPar, nnkStmtList:
        if n.len == 1: result = aux n[0]
        elif n.len == 2:
          result = newNode(aux n[0], ckAction)

      of nnkIntLit:
        result = newNode($n.intVal)

      of nnkStrLit:
        result = newNode("\"" & $n.strval.dumpString() & "\"")

      of nnkCharLit:
        result = newNode("'" & $n.intVal.char & "'")

      of nnkCall:
        var name: string
        if n[0].kind == nnkIdent:
          name = n[0].strVal
        elif n[0].kind == nnkDotExpr:
          name = n[0][0].strVal & "." & n[0][1].strVal
        let n2 = applyTemplate(name, n)
        if n2 != nil:
          result = aux n2
        elif name == "choice":
          var cs: seq[Node]
          for i in 1..<n.len: cs.add aux(n[i])
          result = choice(cs)
        else:
          result = aux(n[1])

      of nnkPrefix:
        # Nim combines all prefix chars into one string. Handle prefixes
        # chars right to left
        let cs = n[0].strVal
        var p = aux n[1]
        for i in 1..cs.len:
          case cs[cs.len-i]:
            of '?': p = ?p
            of '+': p = +p
            of '*': p = *p
            of '!': p = newNode()
            else: p = p
        result = p

      of nnkInfix:
        let (p1, p2) = (aux n[1], aux n[2])
        case n[0].strVal:
          of "*": result = p1 * p2
          of "-": result = p1 - p2
          else: discard

      of nnkBracketExpr:
        let p = aux(n[0])
        if n[1].kind == nnkIntLit:
          result = p{n[1].intVal}
        elif n[1].kind == nnkInfix and n[1][0].eqIdent(".."):
          result = p{n[1][1].intVal..n[1][2].intVal}
        else: discard

      of nnkIdent:
        result = newNode("[" & n.strVal & "]")

      of nnkDotExpr:
        result = newNode("[" & n[0].strVal & "." & n[1].strVal & "]")

      of nnkCurly:
        var cs: CharSet
        for nc in n:
          if nc.kind == nnkCharLit:
            cs.incl nc.intVal.char
          elif nc.kind == nnkInfix:
            if nc[0].kind == nnkIdent and nc[0].eqIdent(".."):
              for c in nc[1].intVal..nc[2].intVal:
                cs.incl c.char
        if cs.card == 0:
          result = newNode("1")
        else:
          result = newNode(dumpSet(cs))

      of nnkCallStrLit:
        case n[0].strVal:
          of "i": result = newNode(n[1].strval)
          of "E": result = newNode("ERROR")
      else:
        discard

  let nnf = nn.flattenChoice
  result = aux(nnf)


