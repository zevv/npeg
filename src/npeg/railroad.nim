
import macros, unicode, strutils


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

proc `$`(n: Node): string =
  let h = n.y1 - n.y0
  let y0 = n.y0
  var l: seq[Rune]
  var ls: seq[seq[Rune]]
  for x in 0..<n.w: l.add ' '.Rune
  for y in 0..<h: ls.add l
               
  proc render(n: Node, x, y: int) =
    for k in n.kids:
      render(k.n, x + k.dx, y + k.dy)
    for s in n.syms:
      let sx = x+s.x+1 - 1
      let sy = y+s.y+1 - y0
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

proc wrap(n: Node): Node =
  result = Node(w: n.w+4, y0: n.y0, y1: n.y1)
  result.kids.add Kid(n: n, dx: 2)
  result.poke(0, 0, "o")
  result.poke(1, 0, "─")
  result.poke(result.w-2, 0, "─")
  result.poke(result.w-1, 0, "o")

proc newNode(s: string): Node =
  let rs = s.toRunes()
  let n = Node(w: rs.len)
  for x in 0..<rs.len:
    n.poke(x, 0, rs[x])
  result = n.pad(1, 1)

proc `*`(n1, n2: Node): Node =
  result = Node(w: n1.w + n2.w + 3, y0: min(n1.y0, n2.y0), y1: max(n1.y1, n2.y1))
  result.kids.add Kid(n: n1, dx: 0)
  result.poke(n1.w+0, 0, "─")
  result.poke(n1.w+1, 0, "»")
  result.poke(n1.w+2, 0, "─")
  result.kids.add Kid(n: n2, dx: n1.w+3)

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

  result = Node(w: wmax+2, y0: y0, y1: y1)
  let x0 = 0
  let x1 = wmax+1

  for i in 0..<ns.len:
    let n = ns[i]
    let pad1 = (wmax-n.w) /% 2
    let pad2 = (wmax-n.w) - pad1
    result.kids.add Kid(n: n.pad(pad1, pad2), dx: 1, dy: dys[i])
      
  for y in 1..<dys[dys.high]:
    result.poke(x0, y, "│")
    result.poke(x1, y, "│")

  result.poke(x0, 0, "┬")
  result.poke(x1, 0, "┬")
  for i in 0..<ns.len-1:
    let n = ns[i]
    if i > 0:
      result.poke(x0, dys[i], "├")
      result.poke(x1, dys[i], "┤")

  result.poke(x0, dys[dys.high], "╰")
  result.poke(x1, dys[dys.high], "╯")

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

macro xfrmChoice(n: untyped): untyped =
  flattenChoice(n)

template _(s: string): untyped = newNode(s)

xfrmChoice:
  let n1 = * _("[aap]") * _("'('") * + _("Digit") * _("')'")
  let n2 = ? ( _("flop") * +_("Word"))
  let n3 = ? (n1 | ?_("1") | * _("bla")) * n2
  echo $n3.wrap

