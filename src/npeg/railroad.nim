
import macros, unicode, tables, strutils, sequtils
import npeg/[grammar,common]

when not defined(js):
  import terminal
else:
  type ForeGroundColor = enum
    fgYellow, fgMagenta, fgGreen, fgWhite, fgCyan, fgRed

const
  fgName = fgYellow
  fgLit = fgMagenta
  fgLine = fgGreen
  fgCap = fgWhite
  fgNonterm = fgCyan
  fgError = fgRed

type

  Sym = object
    x, y: int
    c: Char

  Char = object
    r: Rune
    fg: ForeGroundColor

  Line = seq[Char]

  Grid = seq[Line]

  Node = ref object
    w, y0, y1: int
    syms: seq[Sym]
    kids: seq[Kid]

  Kid = object
    dx, dy: int
    n: Node

# Provide ASCII alternative of box drawing for windows

when defined(windows) or defined(js):
  const asciiTable = [ ("│", "|"), ("─", "-"), ("╭", "."), ("╮", "."),
                       ("╰", "`"), ("╯", "'"), ("┬", "-"), ("├", "|"),
                       ("┤", "|"), ("┴", "-"), ("━", "=") ]

#
# Renders a node to text output
#

proc `$`*(n: Node): string =
  let h = n.y1 - n.y0 + 1
  let y0 = n.y0
  var line: Line
  var grid: Grid
  for x in 0..<n.w:
    line.add Char(r: ' '.Rune)
  for y in 0..<h: grid.add line

  proc render(n: Node, x, y: int) =
    for k in n.kids:
      render(k.n, x + k.dx, y + k.dy)
    for s in n.syms:
      let sx = x+s.x
      let sy = y+s.y - y0
      grid[sy][sx] = s.c
  render(n, 0, 0)
      
  when defined(windows) or defined(js):
    for line in grid:
      for cell in line:
        result.add ($cell.r).multiReplace(asciiTable)
      result.add "\r\n"
  else:
    var fg = fgLine
    for line in grid:
      for cell in line:
        if fg != cell.fg:
          fg = cell.fg
          result.add ansiForegroundColorCode(fg)
        result.add $cell.r
      result.add "\n"
    result.add ansiForegroundColorCode(fgLine)

proc poke(n: Node, fg: ForeGroundColor, cs: varArgs[tuple[x, y: int, s: string]]) =
  for c in cs:
    n.syms.add Sym(x: c.x, y: c.y, c: Char(r: c.s.runeAt(0), fg: fg))

proc pad(n: Node, left, right, top, bottom = 0): Node = 
  result = Node(w: n.w + left + right, y0: n.y0 - top, y1: n.y1 + bottom)
  result.kids.add Kid(n: n, dx: left, dy: 0)
  for x in 0..<left:
    result.poke fgLine, (x, 0, "─")
  for x in n.w+left..<result.w:
    result.poke fgLine, (x, 0, "─")

proc wrap*(n: Node, name: string): Node =
  let namer = (name & " ").toRunes()
  let nl = namer.len()
  result = n.pad(nl+2, 2)
  result.poke fgLine, (nl+0, 0, "o"), (nl+1, 0, "─"), (result.w-2, 0, "─"), (result.w-1, 0, "o")
  for i in 0..<nl:
    result.poke fgName, (i, 0, $namer[i])

proc newNode(s: string, fg = fgLine): Node =
  let rs = s.dumpSubject().toRunes()
  let n = Node(w: rs.len)
  for x in 0..<rs.len:
    n.poke fg, (x, 0, $rs[x])
  result = n.pad(1, 1)

proc newCapNode(n: Node, name = ""): Node =
  result = pad(n, 2, 2)
  result.y0 = n.y0 - 1
  result.y1 = n.y1 + 1
  let (x0, x1, y0, y1) = (1, result.w-2, result.y0, result.y1)
  result.poke fgCap, (x0, y0, "╭"), (x1, y0, "╮"), (x0, y1, "╰"), (x1, y1, "╯")
  for x in x0+1..x1-1:
    result.poke fgCap, (x, y0, "╶"), (x, y1, "╶")
  for y in y0+1..y1-1:
    if y != 0:
      result.poke fgCap, (x0, y, "┆"), (x1, y, "┆")
  let namer = name.toRunes()
  for i in 0..<namer.len:
    result.poke fgCap, ((x1+x0-namer.len)/%2+i, y0, $namer[i])

proc newPrecNode(n: Node, prec: BiggestInt, lr: string): Node =
  let l = lr & $prec & lr
  result = pad(n, if l.len > n.w: l.len-n.w else: 0, 0, 1)
  for i, c in l:
    result.poke fgCap, (result.w/%2 - l.len/%2 + i, -1, $c)

proc `*`(n1, n2: Node): Node =
  result = Node(w: n1.w + n2.w + 1, y0: min(n1.y0, n2.y0), y1: max(n1.y1, n2.y1))
  result.poke fgGreen, (n1.w, 0, "»")
  result.kids.add Kid(n: n1, dx: 0)
  result.kids.add Kid(n: n2, dx: n1.w+1)

proc `?`(n: Node): Node =
  result = n.pad(1, 1, 1, 0)
  let (x1, x2, y1, y2) = (0, n.w+1, -1 + n.y0, 0)
  result.poke fgLine, (x1, y1, "╭"), (x1, y2, "┴"), (x2, y1, "╮"), (x2, y2, "┴")
  for x in x1+1..x2-1:
    result.poke fgLine, (x, y1, "─")
  for y in y1+1..y2-1:
    result.poke fgLine, (x1, y, "│"), (x2, y, "│")
  result.poke fgLine, ((x1+x2)/%2, y1, "»")

proc `+`(n: Node): Node =
  result = n.pad(1, 1, 0, 1)
  let (x1, x2, y1, y2) = (0, n.w+1, 0, n.y1+1)
  result.poke fgLine, (x1, y1, "┬"), (x1, y2, "╰"), (x2, y1, "┬"), (x2, y2, "╯")
  for x in x1+1..x2-1:
    result.poke fgLine, (x, y2, "─")
  for y in y1+1..y2-1:
    result.poke fgLine, (x1, y, "│"), (x2, y, "│")
  result.poke fgLine, ((x1+x2)/%2, y2, "«")

proc `!`(n: Node): Node =
  result = n.pad(0, 0, 1)
  let (x0, x1) = (1, result.w-2)
  for x in x0..x1:
    result.poke fgRed, (x, result.y0, "━")

proc `-`*(p1, p2: Node): Node =
  return !p2 * p1

proc `*`(n: Node): Node = ? + n

proc `@`(n: Node): Node =
  result = *(!n * newNode("1")) * n

proc `&`(n: Node): Node =
  result = ! ! n

proc choice(ns: varArgs[Node]): Node =
  var wmax = 0
  for n in ns:
    wmax = max(wmax, n.w)
  var dys = @[0]
  var dy = 0
  for i in 0..<ns.len-1:
    inc dy, ns[i].y1 - ns[i+1].y0 + 1
    dys.add dy
  result = Node(w: wmax+4, y0: ns[0].y0, y1: dy+ns[ns.high].y1)
  let x0 = 1
  let x1 = wmax+2
  result.poke fgLine, (0, 0, "─"), (result.w-1, 0, "─")
  for i in 0..<ns.len:
    let n = ns[i]
    result.kids.add Kid(n: n.pad(0, wmax-n.w), dx: 2, dy: dys[i])
  for y in 1..<dys[dys.high]:
    result.poke fgLine, (x0, y, "│"), (x1, y, "│")
  result.poke fgLine, (x0, 0, "┬"), (x1, 0, "┬")
  for i in 0..<ns.len-1:
    if i > 0:
      result.poke fgLine, (x0, dys[i], "├"), (x1, dys[i], "┤")
  result.poke fgLine, (x0, dys[dys.high], "╰"), (x1, dys[dys.high], "╯")

proc `{}`*(p: Node, n: BiggestInt): Node =
  result = p
  for i in 1..<n:
    result = result * p

proc `{}`*(p: Node, range: HSlice[system.BiggestInt, system.BiggestInt]): Node =
  result = p{range.a}
  for i in range.a..<range.b:
    result = result * ?p

# This is a simplified parser based on parsePatt(), but lacking any error
# checking. This will always run after parsePatt(), so any errors would already
# have been caught there

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
        result = aux(t.code).flattenChoice()

    case n.kind:

      of nnKPar:
        result = aux n[0]

      of nnkIntLit:
        result = newNode($n.intVal, fgLit)

      of nnkStrLit:
        result = newNode("\"" & $n.strval.dumpSubject() & "\"", fgLit)

      of nnkCharLit:
        result = newNode("'" & $n.intVal.char & "'", fgLit)

      of nnkCall:
        var name: string
        if n[0].kind == nnkIdent:
          name = n[0].strVal
        elif n[0].kind == nnkDotExpr:
          name = n[0].repr
        let n2 = applyTemplate(name, n)
        if n2 != nil:
          result = aux n2
        elif name == "choice":
          result = choice(n[1..^1].map(aux))
        elif n.len == 2:
          result = newCapNode aux(n[1])
        elif n.len == 3:
          result = newCapNode(aux(n[2]), n[1].strVal)

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
            of '!': p = !p
            of '@': p = @p
            of '&': p = &p
            of '>': p = newCapNode(p)
            else: p = p
        result = p

      of nnkInfix:
        case n[0].strVal:
          of "*", "∙": result = aux(n[1]) * aux(n[2])
          of "-": result = aux(n[1]) - aux(n[2])
          of "^": result = newPrecNode(aux(n[1]), intVal(n[2]), "<")
          of "^^": result = newPrecNode(aux(n[1]), intVal(n[2]), ">")
          else: discard

      of nnkBracketExpr:
        let p = aux(n[0])
        if n[1].kind == nnkIntLit:
          result = p{n[1].intVal}
        elif n[1].kind == nnkInfix and n[1][0].eqIdent(".."):
          result = p{n[1][1].intVal..n[1][2].intVal}
        else: discard

      of nnkIdent:
        result = newNode("[" & n.strVal & "]", fgNonterm)

      of nnkDotExpr:
        result = newNode("[" & n.repr & "]", fgNonterm)

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
          result = newNode("1", fgNonterm)
        else:
          result = newNode(dumpSet(cs), fgLit)

      of nnkCallStrLit:
        case n[0].strVal:
          of "i": result = newNode(n[1].strval)
          of "E": result = newNode("ERROR", fgError)

      of nnkBracket:
        result = newNode("[" & n[0].repr & "]", fgNonterm)

      else:
        discard

  let nnf = nn.flattenChoice
  result = aux(nnf)


