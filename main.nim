
import npeg
import macros
import strutils
import tables


type
  Opcode = enum
    opChar, opChoice, opCommit, opComment, opCall, opReturn, opAny

  Inst = object
    op: Opcode
    ch: char
    offset: int
    comment: string
    name: string

  Frame = object
    ip: int
    si: int

  Patt = seq[Inst]

  Patts = Table[string, Patt]


proc `$`*(p: Patt): string =
  for n, i in p.pairs:
    result &= $n & ": " & $i.op
    case i.op:
      of opChar:
        result &= " '" & $i.ch & "'"
      of opChoice, opCommit:
        result &= " " & $(n+i.offset)
      of opCall:
        result &= " " & i.name
      of opComment:
        result &= "# " & i.comment
      else:
        discard
    result &= "\n"

  
#
# Recursively compile a peg pattern to a list of state machine instructions
#

proc buildPatt(patts: Patts, name: string, patt: NimNode): Patt =

  proc aux(n: NimNode): Patt =

    template add(p: Inst|Patt) =
      result.add p

    template addMaybe(p: Patt) =
      add Inst(op: opChoice, offset: p.len+2)
      add p
      add Inst(op: opCommit, offset: -p.len-1)

    case n.kind:
      of nnKPar:
        add aux(n[0])
      of nnkPrefix:
        if n[0].eqIdent("?"):
          addMaybe aux(n[1])
        elif n[0].eqIdent("+"):
          let p = aux n[1]
          add p
          addMaybe p
        elif n[0].eqIdent("*"):
          let p = aux n[1]
          add Inst(op: opChoice, offset: p.len+2)
          add p
          add Inst(op: opCommit, offset: p.len-2)
        else:
          error "Unhandled prefix operator"
      of nnkStrLit:
        for ch in n.strVal:
          add Inst(op: opChar, ch: ch)
      of nnkInfix:
        if n[0].eqIdent("*"):
          add aux(n[1])
          add aux(n[2])
        elif n[0].eqIdent("|"):
          let p1 = aux n[1]
          let p2 = aux n[2]
          add Inst(op: opChoice, offset: p1.len+2)
          add p1
          add Inst(op: opCommit, offset: p2.len+1)
          add p2
        else:
          error "Unhandled infix operator " & n.repr
      of nnkCurlyExpr:
        let p = aux(n[0])
        let min = n[1].intVal
        for i in 1..min:
          add p
        if n.len == 3:
          let max = n[2].intval
          for i in min..max:
            addMaybe p
      of nnkIdent:
        let name = n.strVal
        if name == "_":
          add Inst(op: opAny)
        elif name in patts:
          add patts[name]
        else:
          add Inst(op: opCall, name: n.strVal)
      else:
        error "PEG syntax error"
 
  result.add Inst(op: opComment, comment: "--- start " & name)
  result.add aux(patt)
  result.add Inst(op: opReturn)
  result.add Inst(op: opComment, comment: "--- end " & name)


proc isTerminal(p: Patt): bool =
  for i in p:
    if i.op == opCall:
      return false
  return true


#
# Compile the PEG to a table of patterns
#

proc compile(ns: NimNode): Patts =
  result = initTable[string, Patt]()

  ns.expectKind nnkStmtList
  for n in ns:
    n.expectKind nnkInfix
    n[0].expectKind nnkIdent
    n[1].expectKind nnkIdent
    if not n[0].eqIdent("<-"):
      error("Expected <-")
    let pname = n[1].strVal
    result[pname] = buildPatt(result, pname, n[2])


#
# Link all patterns into a grammar, which is itself again a valid pattern.
# Start with the initial rule, add all other non terminals and fixup opCall
# addresses
#

proc link(patts: Patts, name: string): Patt =

  if name notin patts:
    error "Patts start rule '" & name & "' not found"

  result.add patts[name]

  for n, p in patts:
    if n != name and not p.isTerminal:
      result.add p


template skel(ip: NimNode, cases: untyped) =

  var
    stack: seq[Frame]

  proc trace() =
    echo "ip:" & $ip & " si:" & $si & " s:" & s[si..<s.len]

  proc doComment() =
    inc ip

  proc doChar(c: char) =
    if si < s.len and s[si] == c:
      inc ip
      inc si
    else:
      ip = -1

  proc doAny() =
    if si < s.len:
      inc ip
      inc si
    else:
      ip = -1

  proc doChoice(n: int) =
    stack.add Frame(ip: n, si: si)
    inc ip

  proc doCommit(n: int) =
    stack.del stack.high
    ip = n

  proc doFail() =
    ip = -1

  proc doReturn() =
    echo "return"

  proc doElse() =
    while stack.len > 0 and stack[stack.high].si == -1:
      stack.del stack.high

    if stack.len == 0:
      echo "Error"
      quit 1

    ip = stack[stack.high].ip
    si = stack[stack.high].si
    stack.del stack.high

  while true:
    trace()
    cases


proc mkParser(name: string, program: Patt): NimNode =

  var ip = newIdentNode("ip")
  var cases = nnkCaseStmt.newTree(ip)
  
  for n, i in program.pairs:

    var cmd = replace($i.op, "op", "do") & "("

    case i.op:
      of opChar:
        cmd &= "'" & $i.ch & "'"
      of opChoice, opCommit:
        cmd &= $(n+i.offset)
      of opCall:
        cmd &= "\"" & i.name & "\""
      else:
        discard
    cmd &= ")"

    cases.add nnkOfBranch.newTree(newLit(n), parseStmt(cmd))

  cases.add nnkElse.newTree(parseStmt("doElse()"))

  var body = nnkStmtList.newTree()
  body.add parseStmt("var ip = 0")
  body.add parseStmt("var si = 0")
  body.add getAst skel(ip, cases)

  result = nnkLambda.newTree(newEmptyNode(), newEmptyNode(), newEmptyNode(),
    nnkFormalParams.newTree( newEmptyNode(), nnkIdentDefs.newTree(
        newIdentNode("s"), newIdentNode("string"),
        newEmptyNode()
      )
    ),
    newEmptyNode(), newEmptyNode(),
    body
  )


#
# Convert a pattern to a Nim proc implementing the parser state machine
#

macro peg(name: string, ns: untyped): untyped =
  let grammar = compile(ns)
  let program = link(grammar, name.strVal)
  echo program
  result = mkParser(name.strVal, program)

when true:
  let s = peg "aap":
    aap <- "ab"

  s("abab")



#macro hop(): untyped =
#  result = mkParser()
#  echo result.repr
#
#let fn = hop()
##fn("abab")


when false:
  discard peg "Exp":
    Number <- ("0" | "1" | "2"){1,1}
    TermOp <- "+" | "-"
    FactorOp <- "*" | "/"
    Open <- "("
    Close <- ")"
    Exp <- Term * (TermOp * Term){0,1}
    Term <- Factor * (FactorOp * Factor){0,1}
    Factor <- Number + Open * Exp * Close


when false:
  let s = P"ab" * -P(1)
  echo s

  proc parse(s: string) =

    var
      ip: int
      si: int
      stack: seq[Frame]

    const
      Nowhere = -1
      Fail = -2

    proc doChoice(n: int) =
      stack.add Frame(ip: n, si: si)
      inc ip

    proc doCommit(n: int) =
      stack.del stack.high
      ip = n
      
    proc doChar(c: char) =
      if si < s.len and s[si] == c:
        inc ip
        inc si
      else:
        ip = Fail
    
    proc doAny() =
      if si < s.len:
        inc ip
        inc si
      else:
        ip = Fail

    proc doFail() =
      ip = Fail
    
    while true:
        
      echo "ip:" & $ip & " si:" & $si & " s:" & s[si..<s.len]

      case ip:

        of 0: doChoice(4)
        of 1: doChar('a')
        of 2: doChar('b')
        of 3: doCommit(0)
        of 4: doChoice(8)
        of 5: doAny()
        of 6: doCommit(7)
        of 7: doFail()
        of 8:
          echo "Done"
          quit 0
        of Fail:

          while stack.len > 0 and stack[stack.high].si == Nowhere:
            stack.del stack.high

          if stack.len == 0:
            echo "Error"
            quit 1

          ip = stack[stack.high].ip
          si = stack[stack.high].si
          stack.del stack.high
        else:
          doAssert false, "Boom"

  parse("ababab")
