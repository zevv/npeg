
import macros
import strutils
import tables
import npeg/[common,patt,stack,capture]

type

  RetFrame = int

  BackFrame = tuple
    ip: int
    si: int
    rp: int
    cp: int

  MatchResult* = object
    ok*: bool
    matchLen*: int
    matchMax*: int
    cs*: Captures

  MatchFn* = proc(p: Parser, s: string): MatchResult

  Parser* = ref object
    fn*: proc(p: Parser, s: string): MatchResult
    ip*: int
    si*: int
    simax*: int
    refs*: Table[string, string]
    retStack*: Stack[RetFrame]
    capStack*: Stack[CapFrame]
    backStack*: Stack[BackFrame]


# This macro translates `$1`.. into `capture[0]`.. for use in code block captures

proc mkDollarCaptures(n: NimNode): NimNode =
  if n.kind == nnkNilLit:
    result = nnkDiscardStmt.newTree(newEmptyNode())
  elif n.kind == nnkPrefix and
     n[0].kind == nnkIdent and n[0].eqIdent("$") and
     n[1].kind == nnkIntLit:
    result = nnkBracketExpr.newTree(newIdentNode("capture"), newLit(int(n[1].intVal-1)))
  else:
    result = copyNimNode(n)
    for nc in n:
      result.add mkDollarCaptures(nc)


proc initParser(fn: MatchFn): Parser =
  Parser(
    fn:  fn,
    refs:  initTable[string, string](),
    retStack:  initStack[RetFrame]("return", 8, RETSTACK_MAX),
    capStack:  initStack[CapFrame]("capture", 8),
    backStack:  initStack[BackFrame]("backtrace", 8, BACKSTACK_MAX),
  )


# Template for generating the parsing match proc.
#
# Note: Dummy 'ip' and 'capture' nodes are passed into this template to prevent these
# names from getting mangled so that the code in the `peg` macro can access it.
# I'd love to hear if there are better solutions for this.

template skel(cases: untyped, p: NimNode, capture: NimNode) =

  {.push hint[XDeclaredButNotUsed]: off.}

  let match = proc(p: Parser, s: string): MatchResult =

    # Debug trace. Slow and expensive

    proc doTrace(iname, msg: string) =
      var l: string
      l.add if p.ip >= 0: align($p.ip, 3) else: "   "
      l.add "|" & align($p.si, 3)
      l.add "|" & alignLeft(dumpString($s, p.si, 24), 24)
      l.add "|" & alignLeft(iname, 15)
      l.add "|" & alignLeft(msg, 30)
      l.add "|" & alignLeft(repeat("*", p.backStack.top), 20)
      echo l

    template trace(iname, msg: string) =
      when npegTrace:
        doTrace(iname, msg)

    # State machine instruction handlers

    template opStrFn(s2: string, iname="") =
      trace iname, "str \"" & dumpString(s2) & "\""
      if subStrCmp(s, s.len, p.si, s2):
        inc p.ip
        inc p.si, s2.len
      else:
        p.ip = -1

    template opIStrFn(s2: string, iname="") =
      trace iname, "istr \"" & dumpString(s2) & "\""
      if subIStrCmp(s, s.len, p.si, s2):
        inc p.ip
        inc p.si, s2.len
      else:
        p.ip = -1

    template opSetFn(cs: CharSet, iname="") =
      trace iname, "set " & dumpSet(cs)
      if p.si < s.len and s[p.si] in cs:
        inc p.ip
        inc p.si
      else:
        p.ip = -1

    template opSpanFn(cs: CharSet, iname="") =
      trace iname, "span " & dumpSet(cs)
      while p.si < s.len and s[p.si] in cs:
        inc p.si
      inc p.ip

    template opNopFn(iname="") =
      trace iname, "nop"
      inc p.ip

    template opAnyFn(iname="") =
      trace iname, "any"
      if p.si < s.len:
        inc p.ip
        inc p.si
      else:
        p.ip = -1

    template opChoiceFn(n: int, iname="") =
      trace iname, "choice -> " & $n
      push(p.backstack, (ip:n, si:p.si, rp:p.retStack.top, cp:p.capStack.top))
      inc p.ip

    template opCommitFn(n: int, iname="") =
      trace iname, "commit -> " & $n
      discard pop(p.backStack)
      p.ip = n

    template opPartCommitFn(n: int, iname="") =
      trace iname, "pcommit -> " & $n
      update(p.backStack, si, p.si)
      update(p.backStack, cp, p.capStack.top)
      p.ip = n

    template opCallFn(label: string, offset: int, iname="") =
      trace iname, "call -> " & label & ":" & $(p.ip+offset)
      push(p.retStack, p.ip+1)
      p.ip += offset

    template opJumpFn(label: string, offset: int, iname="") =
      trace iname, "jump -> " & label & ":" & $(p.ip+offset)
      p.ip += offset

    template opCapOpenFn(n: int, capname: string, iname="") =
      let ck = CapKind(n)
      trace iname, "capopen " & $ck & " -> " & $p.si
      push(p.capStack, (cft: cftOpen, si: p.si, ck: ck, name: capname))
      inc p.ip
    
    template opCapCloseFn(n: int, actionCode: untyped, iname="") =
      let ck = CapKind(n)
      trace iname, "capclose " & $ck & " -> " & $p.si
      push(p.capStack, (cft: cftClose, si: p.si, ck: ck, name: ""))
      if ck == ckAction:
        let cs = fixCaptures(s, p.capStack, FixOpen)
        let capture {.inject.} = collectCaptures(cs)
        block:
          actionCode
      elif ck == ckRef:
        let cs = fixCaptures(s, p.capStack, FixOpen)
        let r = collectCapturesRef(cs)
        p.refs[r.key] = r.val
      inc p.ip
    
    template opBackrefFn(refName: string, iname="") =
      # This is a proc because we do not want to export 'contains'
      if refName in p.refs:
        let s2 = p.refs[refName]
        trace iname, "backref " & refName & ":\"" & s2 & "\""
        if subStrCmp(s, s.len, p.si, s2):
          inc p.ip
          inc p.si, s2.len
        else:
          p.ip = -1
      else:
        raise newException(NPegException, "Unknown back reference '" & refName & "'")

    template opReturnFn(iname="") =
      trace iname, "return"
      if p.retStack.top == 0:
        trace iname, "done"
        result.ok = true
        break
      p.ip = pop(p.retStack)

    template opFailFn(iname="") =
      trace iname, "fail"
      if p.backStack.top == 0:
        trace iname, "error"
        break
      (p.ip, p.si, p.retStack.top, p.capStack.top) = pop(p.backStack)

    template opErrFn(msg: string, iname="") =
      trace iname, "err " & msg
      var e = newException(NPegException, "Parsing error at #" & $p.si & ": expected \"" & msg & "\"")
      e.matchLen = p.si
      e.matchMax = p.simax
      raise e

    while true:

      # These cases will be filled in by genCode() which uses this template
      # as the match lambda boilerplate:

      cases

      # Keep track of the highest string index we ever reached, this is a good
      # indication of the location of errors when parsing fails

      if p.si > p.simax:
        p.simax = p.si

    # When the parsing machine is done, close the capture stack and collect all
    # the captures in the match result

    result.matchLen = p.si
    result.matchMax = p.simax
    if result.ok and p.capStack.top > 0:
      result.cs = fixCaptures(s, p.capStack, FixAll)

  {.pop.}

  initParser(match)


# Convert the list of parser instructions into a Nim finite state machine

proc genCode*(patt: Patt): NimNode =

  let pNode = ident("p")
  let ipNode = newDotExpr(pNode, ident("ip"))
  var cases = nnkCaseStmt.newTree(ipNode)

  for n, i in patt.pairs:

    let call = nnkCall.newTree(ident($i.op & "Fn"))

    case i.op:
      of opStr, opIStr:
        call.add newLit(i.str)

      of opSet, opSpan:
        let setNode = nnkCurly.newTree()
        for c in i.cs: setNode.add newLit(c)
        call.add setNode

      of opChoice, opCommit, opPartCommit:
        call.add newLit(n + i.offset)

      of opCall, opJump:
        call.add newLit(i.callLabel)
        call.add newLit(i.callOffset)

      of opCapOpen:
        call.add newLit(i.capKind.int)
        call.add newLit(i.capName)

      of opCapClose:
        call.add newLit(i.capKind.int)
        call.add mkDollarCaptures(i.capAction)

      of opBackref:
        call.add newLit(i.refName)

      of opErr:
        call.add newStrLitNode(i.msg)

      of opReturn, opAny, opNop, opFail:
        discard

    when npegTrace:
      call.add newStrLitNode(i.name)

    cases.add nnkOfBranch.newTree(newLit(n), call)

  cases.add nnkElse.newTree(parseStmt("opFailFn()"))
  result = getAst skel(cases, pNode, ident "capture")

  when false:
    echo result.repr


