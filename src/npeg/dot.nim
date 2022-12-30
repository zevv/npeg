
import tables
import strutils

type
  Dot* = ref object
    name: string
    edges: Table[string, bool]
    nodes: seq[string]

const colors = {
  "inline": "grey60",
  "call": "blue",
}.toTable()


proc escape(s: string): string =
  return s.replace(".", "_").replace("-", "_")

proc newDot*(name: string): Dot =
  return Dot(name: name)

proc add*(d: Dot, n1, n2: string, meth: string) =
  if d != nil:
    let l = "  " & n1.escape & " -> " & n2.escape & " [ color=" & colors[meth] & "];"
    d.edges[l] = true

proc addPatt*(d: Dot, name: string, len: int) =
  if d != nil:
    var color = "black"
    if len > 10: color = "orange"
    if len > 100: color = "red"
    d.nodes.add "  " & name.escape &
                " [ fillcolor=lightgrey color=" & color & " label=\"" & name & "/" & $len & "\"];"

proc dump*(d: Dot) =
  const npegDotDir {.strdefine.}: string = ""
  when npegDotDir != "":
    let fname = npegDotDir & "/" & d.name & ".dot"
    echo "Dumping dot graph file to " & fname & "..."

    var o: string
    o.add "digraph dot {\n"
    o.add "  graph [ center=true, margin=0.2, nodesep=0.1, ranksep=0.3 ];\n"
    o.add "  node [ shape=box, style=\"rounded,filled\" width=0, height=0, fontname=Helvetica, fontsize=10];\n"
    o.add "  edge [ fontname=Helvetica, fontsize=10];\n"
    for k, v in d.edges:
      o.add k & "\n"
    for n in d.nodes:
      o.add n & "\n"
    o.add "}\n"
    writeFile fname, o

