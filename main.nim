
import npeg
import macros
import strutils
import tables


type
  Opcode = enum
    opChar, opChoice, opCommit, opComment, opCall, opReturn, opAny

  Inst = object
    case op: Opcode
      of opChoice, opCommit:
        offset: int
      of opChar:
        ch: char
      of opComment:
        comment: string
      of opCall:
        name: string
        address: int
      else:
        discard

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
        result &= " " & i.name & ":" & $i.address
      of opComment:
        result &= "# " & i.comment
      else:
        discard
    result &= "\n"

  
#
# Recursively compile a peg pattern to a sequence of parser instructions
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
          add Inst(op: opCommit, offset: -p.len-1)
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
 
  result.add Inst(op: opComment, comment: "start " & name)
  result.add aux(patt)
  result.add Inst(op: opComment, comment: "end " & name)


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

  var symTab = newTable[string, int]()

  result.add patts[name]
  symTab[name] = result.len
  result.add Inst(op: opReturn)

  for n, p in patts:
    if n != name:
      symTab[n] = result.len
      result.add p
      result.add Inst(op: opReturn)

  # Fixup call addresses

  for i in result.mitems:
    if i.op == opCall:
      i.address = symtab[i.name]

  echo symtab

template skel(cases: untyped) =


  template trace(msg: string) =
    when true:
      echo "ip:" & $ip & " msg:" & msg & " si:" & $si & " s:" & s[si..<s.len]

  proc opCommentFn(msg: string) =
    trace " \e[1m" & msg & "\e[0m"
    inc ip

  proc opCharFn(c: char) =
    trace " char '" & c & "'"
    if si < s.len and s[si] == c:
      inc ip
      inc si
    else:
      ip = -1

  proc opAnyFn() =
    trace " any"
    if si < s.len:
      inc ip
      inc si
    else:
      ip = -1

  proc opChoiceFn(n: int) =
    trace " choice " & $n
    stack.add Frame(ip: n, si: si)
    inc ip

  proc opCommitFn(n: int) =
    trace " commit " & $n
    stack.del stack.high
    ip = n

  proc opFailFn() =
    trace " fail"
    ip = -1

  proc opCallFn(label: string, address: int) =
    trace " call " & label & ":" & $address
    stack.add Frame(ip: ip+1, si: si)
    ip = address

  template opReturnFn() =
    trace " return"
    ip = stack[stack.high].ip
    stack.del stack.high

  proc opElseFn() =
    trace " fail"
    while stack.len > 0 and stack[stack.high].si == -1:
      stack.del stack.high

    if stack.len == 0:
      trace " error"
      quit 1

    ip = stack[stack.high].ip
    si = stack[stack.high].si
    stack.del stack.high

  while true:
    cases


#
# Convert the list of parser instructions into a Nim finite state machine
#

proc gencode(name: string, program: Patt): NimNode =

  # Create case handler for each instruction

  var cases = nnkCaseStmt.newTree(ident("ip"))
  cases.add nnkElse.newTree(parseStmt("opElseFn()"))
  
  for n, i in program.pairs:
    var cmd = $i.op & "Fn("
    case i.op:
      of opChar:             cmd &= "'" & $i.ch & "'"
      of opChoice, opCommit: cmd &= $(n+i.offset)
      of opCall:             cmd &= "\"" & i.name & "\"" & ", " & $i.address
      of opComment:          cmd &= "\"" & i.comment & "\""
      else: discard
    cmd &= ")"
    cases.add nnkOfBranch.newTree(newLit(n), parseStmt(cmd))

  var body = nnkStmtList.newTree()
  body.add parseStmt("var ip {.goto.} = 0")
  body.add parseStmt("var si = 0")
  body.add parseStmt("var stack: seq[Frame]")
  body.add getAst skel(cases)

  # Return parser lambda function containing 'body'

  result = nnkLambda.newTree(newEmptyNode(), newEmptyNode(), newEmptyNode(),
    nnkFormalParams.newTree( newEmptyNode(), nnkIdentDefs.newTree(
        newIdentNode("s"), newIdentNode("string"),
        newEmptyNode()
      )
    ),
    newEmptyNode(), newEmptyNode(),
    body
  )

  #echo cases.repr


#
# Convert a pattern to a Nim proc implementing the parser state machine
#

macro peg(name: string, ns: untyped): untyped =
  let grammar = compile(ns)
  let program = link(grammar, name.strVal)
  echo program
  gencode(name.strVal, program)

when true:
  let s = peg "aap":
    aap <- ab * _ * ab
    ab <- "ab"
  s("abcab")


when false:
  let s = peg "exp":
    digit <- ("0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9")
    number <- +digit
    termOp <- "+" | "-"
    factorOp <- "*" | "/"
    open <- "("
    close <- ")"
    exp <- term * +(termOp * term)
    term <- factor * +(factorOp * factor)
    factor <- number | open * exp * close
  s("13")

