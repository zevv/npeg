
import macros
import strutils
import tables

export escape

const npegTrace = defined(npegTrace)

type
  Opcode = enum
    opChoice, opCommit, opPartCommit, opCall, opReturn, opAny, opSet, opStr,
    opIStr, opFail

  Inst = object
    case op: Opcode
      of opChoice, opCommit, opPartCommit:
        offset: int
      of opStr, opIStr:
        str: string
      of opCall:
        name: string
        address: int
      of opSet:
        cs: set[char]
      of opFail, opReturn, opAny:
        discard

  Frame* = object
    ip: int
    si: int

  Patt = seq[Inst]

  Patts = Table[string, Patt]


proc dumpset(cs: set[char]): string =
  proc esc(c: char): string =
    case c:
      of '\n': result = "\\n"
      of '\r': result = "\\r"
      of '\t': result = "\\t"
      else: result = $c
    result = "'" & result & "'"
  result.add "{"
  var c = 0
  while c <= 255:
    let first = c
    while c <= 255 and c.char in cs:
      inc c
    if (c - 1 == first):
      result.add esc(first.char) & ","
    elif c - 1 > first:
      result.add esc(first.char) & ".." & esc((c-1).char) & ","
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
      of opChoice, opCommit, opPartCommit:
        result &= " " & $(n+i.offset)
      of opCall:
        result &= " " & i.name & ":" & $i.address
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

proc buildPatt(patts: Patts, name: string, patt: NimNode): Patt =

  proc aux(n: NimNode): Patt =

    template add(p: Inst|Patt) =
      result.add p

    template addLoop(p: Patt) =
      add Inst(op: opChoice, offset: p.len+2)
      add p
      add Inst(op: opPartCommit, offset: -p.len)

    template addMaybe(p: Patt) =
      add Inst(op: opChoice, offset: p.len + 2)
      add p
      add Inst(op: opCommit, offset: 1)

    case n.kind:
      of nnKPar, nnkStmtList:
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
          addLoop p
        elif n[0].eqIdent("*"):
          addLoop p
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
          if p1.isset and p2.isset:
            add Inst(op: opSet, cs: p1[0].cs - p2[0].cs)
          else:
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
 
  result = aux(patt)


#
# Compile the PEG to a table of patterns
#

proc compile(ns: NimNode): Patts =
  result = initTable[string, Patt]()

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
# Template for generating the parsing match proc.  A dummy 'ip' node is passed
# into this template to prevent its name from getting mangled so that the code
# in the `peg` macro can access it
#

template skel(cases: untyped, ip: NimNode) =

  {.push hint[XDeclaredButNotUsed]: off.}

  let match = proc(s: string): bool =

    var ip = 0
    var si = 0

    # Stack management

    var sp = 0
    var stack = newSeq[Frame](64)

    template spush(ip2: int, si2: int = -1) =
      if sp >= stack.len:
        stack.setlen stack.len*2
      stack[sp].ip = ip2
      stack[sp].si = si2
      inc sp
    template spop() =
      assert sp > 0
      dec sp
    template spop(ip2: var int) =
      assert sp > 0
      dec sp
      ip2 = stack[sp].ip
    template spop(ip2, si2: var int) =
      assert sp > 0
      dec sp
      ip2 = stack[sp].ip
      si2 = stack[sp].si

    # Debug trace. Slow and expensive

    template trace(msg: string) =
      when npegTrace:
        let si2 = min(si+10, s.len-1)
        var l = align($ip, 3) &
             " | " & align($si, 3) &
             " " & alignLeft(s[si..si2], 24) &
             "| " & alignLeft(msg, 30) &
             "| " & alignLeft(repeat("*", sp), 20)
        if sp > 0:
          l.add $stack[sp-1]
        echo l

    # Helper procs

    proc subStrCmp(s: string, si: int, s2: string): bool =
      if si > s.len - s2.len:
        return false
      for i in 0..<s2.len:
        if s[si+i] != s2[i]:
          return false
      return true

    # State machine instruction handlers
    
    template opIStrFn(s2: string) =
      let l = s2.len
      if si <= s.len - l and s[si..<si+l] == s2:
        inc ip
        inc si, l
      else:
        ip = -1
      trace s2.escape

    template opStrFn(s2: string) =
      if subStrCmp(s, si, s2):
        inc ip
        inc si, s2.len
      else:
        ip = -1
      trace "str " & s2.escape

    template opSetFn(cs: set[char]) =
      if si < s.len and s[si] in cs:
        inc ip
        inc si
      else:
        ip = -1
      trace dumpset(cs)

    template opAnyFn() =
      if si < s.len:
        inc ip
        inc si
      else:
        ip = -1
      trace "any"

    template opChoiceFn(n: int) =
      spush(n, si)
      inc ip
      trace "choice -> " & $n

    template opCommitFn(n: int) =
      spop()
      trace "commit -> " & $n
      ip = n

    template opPartCommitFn(n: int) =
      assert sp > 0
      #stack[sp].ip = ip
      stack[sp-1].si = si
      ip = n
      trace "pcommit -> " & $n

    template opCallFn(label: string, address: int) =
      spush(ip+1)
      ip = address
      trace "call -> " & label & ":" & $address

    template opReturnFn() =
      if sp == 0:
        trace "done"
        return true
      spop(ip)
      trace "return"

    template opFailFn() =
      while sp > 0 and stack[sp-1].si == -1:
        spop()

      if sp == 0:
        trace "\e[31;1merror\e[0m --------------"
        return false

      spop(ip, si)
      trace "fail -> " & $ip

    while true:
      cases
  
  {.pop.}

  match


#
# Convert the list of parser instructions into a Nim finite state machine
#

proc gencode(name: string, program: Patt): NimNode =

  let ipNode = ident("ip")
  var cases = nnkCaseStmt.newTree(ipNode)
  cases.add nnkElse.newTree(parseStmt("opFailFn()"))

  for n, i in program.pairs:
    let call = nnkCall.newTree(ident($i.op & "Fn"))
    case i.op:
      of opStr, opIStr:
        call.add newStrLitNode(i.str)
      of opSet:
        let setNode = nnkCurly.newTree()
        for c in i.cs: setNode.add newLit(c)
        call.add setNode
      of opChoice, opCommit, opPartCommit:
        call.add newIntLitNode(n + i.offset)
      of opCall:
        call.add newStrLitNode(i.name)
        call.add newIntLitNode(i.address)
      else: discard
    cases.add nnkOfBranch.newTree(newLit(n), call)

  result = getAst skel(cases, ipNode)


#
# Convert a pattern to a Nim proc implementing the parser state machine
#

macro peg*(name: string, ns: untyped): untyped =
  let grammar = compile(ns)
  let patt = link(grammar, name.strVal)
  when npegTrace:
    echo patt
  gencode(name.strVal, patt)


macro patt*(ns: untyped): untyped =
  var dummy = initTable[string, Patt]()
  var patt = buildPatt(dummy, "p", ns)
  patt.add Inst(op: opReturn)
  when npegTrace:
    echo patt
  gencode("p", patt)

