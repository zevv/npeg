
import npeg
import macros
import strutils
import tables


type
  Opcode = enum
    opChoice, opCommit, opComment, opCall, opReturn, opAny, opSet, opStr,
    opIStr, opFail

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
      of opFail, opReturn, opAny:
        discard

  Frame = object
    ip: int
    si: int

  Patt = seq[Inst]

  Patts = Table[string, Patt]


proc dumpset(cs: set[char]): string =
  result.add "{"
  var c = 0
  while c <= 255:
    let first = c
    while c.char in cs and c <= 255:
      inc c
    if (c - 1 == first):
      result.add "'" & $first.char & "',"
    elif c - 1 > first:
      result.add "'" & $first.char & "'..'" & $(c-1).char & "',"
    inc c
  if result[result.len-1] == ',': result.setLen(result.len-1)
  result.add "}"


proc `$`*(p: Patt): string =
  for n, i in p.pairs:
    result &= $n & ": " & $i.op
    case i.op:
      of opStr:
        result &= escape(i.str)
      of opIStr:
        result &= "i" & escape(i.str)
      of opSet:
        result &= " '" & dumpset(i.cs) & "'"
      of opChoice, opCommit:
        result &= " " & $(n+i.offset)
      of opCall:
        result &= " " & i.name & ":" & $i.address
      of opComment:
        result &= " \e[1m" & i.comment & "\e[0m"
      of opFail, opReturn, opAny:
        discard
    result &= "\n"


#
# Some tests on patterns
#

proc isSet(p: Patt): bool =
  p.len == 1 and p[0].op == opSet 

  
#
# Recursively compile a peg pattern to a sequence of parser instructions
#
# Atoms:
#    '.'           literal character
#    "..."         literal string
#   i"..."         case insensitive string
#    _             matches any character
#    {}            empty set, always matches
#    {'x'..'y'}    range from 'x' to 'y', inclusive
#    {'x','y'}     set
#  
# Grammar rules:
#   (P)            grouping
#   -P             matches everything but P
#    P1 * P2       concatenation
#    P1 | P2       ordered choice
#    P1 - P2       matches P1 if P1 does not match
#   ?P             conditional, 0 or 1 times
#   *P             0 or more times P
#   +P             1 or more times P
#    P{n}          exactly n times P
#    P{m..n}       m to n times p
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
      of nnkStrLit:
        add Inst(op: opStr, str: n.strVal)
      of nnkCharLit:
        add Inst(op: opStr, str: $n.intVal.char)
      of nnkPrefix:
        let p = aux n[1]
        if n[0].eqIdent("?"):
          addMaybe p
        elif n[0].eqIdent("+"):
          add p
          addMaybe p
        elif n[0].eqIdent("*"):
          add Inst(op: opChoice, offset: p.len+2)
          add p
          add Inst(op: opCommit, offset: -p.len-1)
        elif n[0].eqIdent("-"):
          add Inst(op: opChoice, offset: p.len + 3)
          add p
          add Inst(op: opCommit, offset: 1)
          add Inst(op: opFail)
        else:
          error "PEG: Unhandled prefix operator"
      of nnkInfix:
        let p1 = aux n[1]
        let p2 = aux n[2]
        if n[0].eqIdent("*"):
          add p1
          add p2
        elif n[0].eqIdent("-"):
          add Inst(op: opChoice, offset: p2.len + 3)
          add p2
          add Inst(op: opCommit, offset: 1)
          add Inst(op: opFail)
          add p1
        elif n[0].eqIdent("|"):
          if p1.isset and p2.isset:
            add Inst(op: opSet, cs: p1[0].cs + p2[0].cs)
          else:
            add Inst(op: opChoice, offset: p1.len+2)
            add p1
            add Inst(op: opCommit, offset: p2.len+1)
            add p2
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
        if name in patts:
          add patts[name]
        else:
          add Inst(op: opCall, name: n.strVal)
      of nnkCurly:
        var cs: set[char]
        for nc in n:
          if nc.kind == nnkCharLit:
            cs.incl nc.intVal.char
          elif nc.kind == nnkInfix and nc[0].kind == nnkIdent and nc[0].eqIdent(".."):
            for c in nc[1].intVal..nc[2].intVal:
              cs.incl c.char
          else:
            error "PEG: syntax error: " & n.repr & "\n" & n.astGenRepr
        if cs.card == 0:
          add Inst(op: opAny)
        else:
          add Inst(op: opSet, cs: cs)
      of nnkCallStrLit:
        if n[0].eqIdent("i"):
          add Inst(op: opIStr, str: n[1].strVal)
        else:
          error "PEG: unhandled string prefix"
      else:
        error "PEG: syntax error: " & n.repr & "\n" & n.astGenRepr
 
  #result.add Inst(op: opComment, comment: "start " & name)
  result.add aux(patt)
  #result.add Inst(op: opComment, comment: "end " & name)


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

proc link(patts: Patts, initial_name: string): Patt =

  if initial_name notin patts:
    error "inital pattern '" & initial_name & "' not found"

  var grammar: Patt
  var symTab = newTable[string, int]()

  # Recursively emit a pattern, and all patterns it calls which are
  # not yet emitted

  proc emit(name: string) =
    echo "Emit rule " & name
    let patt = patts[name]
    symTab[name] = grammar.len
    grammar.add patt
    grammar.add Inst(op: opReturn)

    for i in patt:
      if i.op == opCall and i.name notin symTab:
        emit i.name
  
  emit initial_name

  # Fixup grammar call addresses

  for i in grammar.mitems:
    if i.op == opCall:
      i.address = symtab[i.name]

  return grammar

#
# Template for generating the parsing match proc
#

template skel(cases: untyped) =

  template trace(msg: string) =
    when true:
      let si2 = min(si+10, s.len-1)
      echo align($ip, 3) &
           " | " & align($si, 3) & 
           " " & alignLeft(escape(s[si..si2]), 24) & "| " &
           alignLeft(msg, 20)

  template opCommentFn(msg: string) =
    trace "\e[1m" & msg & "\e[0m"
    inc ip
  
  template opIStrFn(s2: string) =
    trace "str " & s2.escape
    let l = s2.len
    if si <= s.len - l and cmpIgnoreCase(s[si..<si+l], s2) == 0:
      inc ip
      inc si, l
    else:
      ip = -1
  
  template opStrFn(s2: string) =
    trace s2.escape
    let l = s2.len
    if si <= s.len - l and s[si..<si+l] == s2:
      inc ip
      inc si, l
    else:
      ip = -1

  template opSetFn(cs: set[char]) =
    trace dumpset(cs)
    if si < s.len and s[si] in cs:
      inc ip
      inc si
    else:
      ip = -1

  template opAnyFn() =
    trace "any"
    if si < s.len:
      inc ip
      inc si
    else:
      ip = -1

  template opChoiceFn(n: int) =
    stack.add Frame(ip: n, si: si)
    trace "choice " & $n
    inc ip

  template opCommitFn(n: int) =
    stack.del stack.high
    trace "commit " & $n
    ip = n

  template opCallFn(label: string, address: int) =
    stack.add Frame(ip: ip+1, si: -1)
    trace "call " & label & ":" & $address
    ip = address

  template opReturnFn() =
    if stack.len == 0:
      trace "done"
      return
    ip = stack[stack.high].ip
    stack.del stack.high
    trace "return"

  template opFailFn() =
    while stack.len > 0 and stack[stack.high].si == -1:
      stack.del stack.high
    

    if stack.len == 0:
      trace "\e[31;1merror\e[0m --------------"
      return

    ip = stack[stack.high].ip
    si = stack[stack.high].si
    stack.del stack.high
    trace "fail"

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
  block:
    let s = peg "aap":
      a <- "a"
      aap <- a * *('(' * aap * ')')
    s("a(a)((a))")


when true:
  block:
    let s = peg "http":
      space                 <- ' '
      crlf                  <- '\n' | "\r\n"
      meth                  <- "GET" | "POST" | "PUT"
      proto                 <- "HTTP"
      version               <- "1.0" | "1.1"
      alpha                 <- {'a'..'z','A'..'Z'}
      digit                 <- {'0'..'9'}
      url                   <- +alpha
      eof                   <- -{}

      req                   <- meth * space * url * space * proto * "/" * version

      header_content_length <- i"Content-Length: " * +digit
      header_other          <- +(alpha | '-') * ": " * +({}-crlf)
    
      header                <- header_content_length | header_other
      http                  <- req * crlf * *(header * crlf) * eof

    s """
POST flop HTTP/1.1
Content-Type: text/plain
content-length: 23
"""

when false:
  block:
    let s = peg "line":
      ws       <- *' '
      digit    <- {'0'..'9'} * ws
      number   <- +digit * ws
      termOp   <- {'+', '-'} * ws
      factorOp <- {'*', '/'} * ws
      open     <- '(' * ws
      close    <- ')' * ws
      eol      <- -{}
      exp      <- term * *(termOp * term)
      term     <- factor * *(factorOp * factor)
      factor   <- number | (open * exp * close)
      line     <- ws * exp * eol
    s("13 + 5 * (2+1)")

