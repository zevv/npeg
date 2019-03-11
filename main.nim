
import npeg
import macros
import strutils
import tables


type
  Opcode = enum
    opChoice, opCommit, opComment, opCall, opReturn, opAny, opSet, opStr,
    opIStr

  Inst = object
    case op: Opcode
      of opChoice, opCommit:
        offset: int
      of opStr, opIStr:
        str: string
      of opComment:
        comment: string
      of opCall:
        name: string
        address: int
      of opSet:
        cs: set[char]
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
      of opStr:
        result &= escape(i.str)
      of opIStr:
        result &= "i" & escape(i.str)
      of opSet:
        result &= " '" & $i.cs & "'"
      of opChoice, opCommit:
        result &= " " & $(n+i.offset)
      of opCall:
        result &= " " & i.name & ":" & $i.address
      of opComment:
        result &= " \e[1m" & i.comment & "\e[0m"
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
          error "PEG: Unhandled prefix operator"
      of nnkStrLit:
        add Inst(op: opStr, str: n.strVal)
      of nnkCharLit:
        add Inst(op: opStr, str: $n.intVal.char)
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
        elif n[0].eqIdent(".."):
          var cs: set[char]
          for c in n[1].intVal..n[2].intVal: cs.incl c.char
          add Inst(op: opSet, cs: cs)
        else:
          error "PEG: Unhandled infix operator " & n.repr
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
      of nnkCallStrLit:
        if n[0].eqIdent("i"):
          add Inst(op: opIStr, str: n[1].strVal)
        else:
          error "PEG: unhandled string prefix"
      else:
        error "PEG: syntax error: " & n.repr & "\n" & n.astGenRepr
 
  result.add Inst(op: opComment, comment: "start " & name)
  result.add aux(patt)
  #result.add Inst(op: opComment, comment: "end " & name)


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

template skel(cases: untyped) =

  template trace(msg: string) =
    when true:
      echo "ip:" & $ip & " " & msg & " si:" & $si & " s:" & escape(s[si..si+10])

  template opCommentFn(msg: string) =
    trace " \e[1m" & msg & "\e[0m"
    inc ip
  
  template opIStrFn(s2: string) =
    trace " str " & s2.escape
    let l = s2.len
    if si <= s.len - l and cmpIgnoreCase(s[si..<si+l], s2) == 0:
      inc ip
      inc si, l
    else:
      ip = -1
  
  template opStrFn(s2: string) =
    trace " str " & s2.escape
    let l = s2.len
    if si <= s.len - l and s[si..<si+l] == s2:
      inc ip
      inc si, l
    else:
      ip = -1

  template opSetFn(cs: set[char]) =
    trace " set " & $cs
    if si < s.len and s[si] in cs:
      inc ip
      inc si
    else:
      ip = -1

  template opAnyFn() =
    trace " any"
    if si < s.len:
      inc ip
      inc si
    else:
      ip = -1

  template opChoiceFn(n: int) =
    trace " choice " & $n
    stack.add Frame(ip: n, si: si)
    inc ip

  template opCommitFn(n: int) =
    trace " commit " & $n
    stack.del stack.high
    ip = n

  template opCallFn(label: string, address: int) =
    trace " call " & label & ":" & $address
    stack.add Frame(ip: ip+1, si: -1)
    ip = address

  template opReturnFn() =
    trace " return"
    if stack.len == 0:
      trace "done ----------------"
      return
    ip = stack[stack.high].ip
    stack.del stack.high

  template opFailFn() =
    trace " fail"
    while stack.len > 0 and stack[stack.high].si == -1:
      stack.del stack.high

    if stack.len == 0:
      trace "\e[31;1merror\e[0m --------------"
      return

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
  cases.add nnkElse.newTree(parseStmt("opFailFn()"))
  
  for n, i in program.pairs:
    var cmd = $i.op & "Fn("
    case i.op:
      of opStr, opIStr:      cmd &= escape(i.str)
      of opSet:              cmd &= $i.cs 
      of opChoice, opCommit: cmd &= $(n+i.offset)
      of opCall:             cmd &= "\"" & i.name & "\"" & ", " & $i.address
      of opComment:          cmd &= "\"" & i.comment & "\""
      else: discard
    cmd &= ")"
    cases.add nnkOfBranch.newTree(newLit(n), parseStmt(cmd))

  var body = nnkStmtList.newTree()
  body.add parseStmt("var ip = 0")
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

  #echo result.repr


#
# Convert a pattern to a Nim proc implementing the parser state machine
#

macro peg(name: string, ns: untyped): untyped =
  let grammar = compile(ns)
  let program = link(grammar, name.strVal)
  echo program
  gencode(name.strVal, program)

when false:
  let s = peg "aap":
    ab <- "ab"
    aap <- ab * _ * ab
  s("abcab")


when true:
  let s = peg "http":
    space <- " "
    crlf <- '\n' | "\r\\nn"
    meth <- "GET" | "POST" | "PUT"
    proto <- "HTTP"
    version <- "1.0" | "1.1"
    alpha <- ('a'..'z') | ('A'..'Z')
    digit <- ('0'..'9')
    url <- +alpha
    req <- meth * space * url * space * proto * "/" * version * crlf

    header_content_length <- i"Content-Length: " * +digit
    header_other <- +(alpha | '-') * ": "
  
    header <- header_content_length | header_other
    http <- req * *header

  s """
POST flop HTTP/1.1
content-length: 23
Content-Type: text/plain
"""


when false:
  let s = peg "number":
    digit <- '0'..'9'
    number <- digit * digit * *digit
    termOp <- "+" | "-"
    factorOp <- "*" | "/"
    open <- "("
    close <- ")"
    exp <- term * +(termOp * term)
    term <- factor * +(factorOp * factor)
    factor <- number | open * exp * close
  s("13")

