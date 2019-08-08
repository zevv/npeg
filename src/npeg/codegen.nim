
import macros
import strutils
import tables
import npeg/[common,patt,stack,capture]

type

  RetFrame* = int

  BackFrame* = tuple
    ip: int
    si: int
    rp: int
    cp: int

  MatchResult* = object
    ok*: bool
    matchLen*: int
    matchMax*: int
    cs*: Captures

  MatchState* = object
    ip*: int
    si*: int
    simax*: int
    refs*: Table[string, string]
    retStack*: Stack[RetFrame]
    capStack*: Stack[CapFrame]
    backStack*: Stack[BackFrame]

  Parser*[T] = object
    fn*: proc(ms: var MatchState, s: Subject, userdata: var T): MatchResult


# This macro translates `$1`.. into `capture[0]`.. for use in code block captures

proc mkDollarCaptures(n: NimNode): NimNode =
  if n.kind == nnkPrefix and
       n[0].kind == nnkIdent and n[0].eqIdent("$") and
       n[1].kind == nnkIntLit:
    let i = int(n[1].intVal-1)
    result = quote do:
      capture[`i`].s
  elif n.kind == nnkNilLit:
    result = quote do:
      discard
  else:
    result = copyNimNode(n)
    for nc in n:
      result.add mkDollarCaptures(nc)


proc newMatchState*(): MatchState =
  result = MatchState(
    retStack: initStack[RetFrame]("return", 8, npegRetStackSize),
    capStack: initStack[CapFrame]("capture", 8),
    backStack: initStack[BackFrame]("backtrace", 8, npegBackStackSize),
  )


# Template for generating the parsing match proc.
#
# Note: Dummy 'ms', 'userdata' and 'capture' nodes are passed into this
# template to prevent these names from getting mangled so that the code in the
# `peg` macro can access it.  I'd love to hear if there are better solutions
# for this.

template skel(T: untyped, cases: untyped, ms: NimNode, s: NimNode, userdata: NimNode, capture: NimNode) =

  {.push hint[XDeclaredButNotUsed]: off.}

  let match = proc(ms: var MatchState, s: Subject, userdata: var T): MatchResult =

    # Debug trace. Slow and expensive

    proc doTrace(iname, msg: string) =
      var l: string
      l.add if ms.ip >= 0: align($ms.ip, 3) else: "   "
      l.add "|" & align($ms.si, 3)
      l.add "|" & alignLeft(dumpString($s, ms.si, 24), 24)
      l.add "|" & alignLeft(iname, 15)
      l.add "|" & alignLeft(msg, 30)
      l.add "|" & alignLeft(repeat("*", ms.backStack.top), 20)
      echo l

    template trace(iname, msg: string) =
      when npegTrace:
        doTrace(iname, msg)

    # State machine instruction handlers

    proc opStrFn(ms: var MatchState, s: Subject, s2: string, iname="") =
      trace iname, "str \"" & dumpString(s2) & "\""
      if subStrCmp(s, s.len, ms.si, s2):
        inc ms.ip
        inc ms.si, s2.len
      else:
        ms.ip = -1

    proc opIStrFn(ms: var MatchState, s: Subject, s2: string, iname="") =
      trace iname, "istr \"" & dumpString(s2) & "\""
      if subIStrCmp(s, s.len, ms.si, s2):
        inc ms.ip
        inc ms.si, s2.len
      else:
        ms.ip = -1

    proc opSetFn(ms: var MatchState, s: Subject, cs: CharSet, iname="") =
      trace iname, "set " & dumpSet(cs)
      if ms.si < s.len and s[ms.si] in cs:
        inc ms.ip
        inc ms.si
      else:
        ms.ip = -1

    proc opSpanFn(ms: var MatchState, s: Subject, cs: CharSet, iname="") =
      trace iname, "span " & dumpSet(cs)
      while ms.si < s.len and s[ms.si] in cs:
        inc ms.si
      inc ms.ip

    proc opNopFn(ms: var MatchState, s: Subject, iname="") =
      trace iname, "nop"
      inc ms.ip

    proc opAnyFn(ms: var MatchState, s: Subject, iname="") =
      trace iname, "any"
      if ms.si < s.len:
        inc ms.ip
        inc ms.si
      else:
        ms.ip = -1

    proc opChoiceFn(ms: var MatchState, s: Subject, n: int, iname="") =
      trace iname, "choice -> " & $n
      push(ms.backStack, (ip:n, si:ms.si, rp:ms.retStack.top, cp:ms.capStack.top))
      inc ms.ip

    proc opCommitFn(ms: var MatchState, s: Subject, n: int, iname="") =
      trace iname, "commit -> " & $n
      discard pop(ms.backStack)
      ms.ip = n

    proc opPartCommitFn(ms: var MatchState, s: Subject, n: int, iname="") =
      trace iname, "pcommit -> " & $n
      update(ms.backStack, si, ms.si)
      update(ms.backStack, cp, ms.capStack.top)
      ms.ip = n

    proc opCallFn(ms: var MatchState, s: Subject, label: string, offset: int, iname="") =
      trace iname, "call -> " & label & ":" & $(ms.ip+offset)
      push(ms.retStack, ms.ip+1)
      ms.ip += offset

    proc opJumpFn(ms: var MatchState, s: Subject, label: string, offset: int, iname="") =
      trace iname, "jump -> " & label & ":" & $(ms.ip+offset)
      ms.ip += offset

    proc opCapOpenFn(ms: var MatchState, s: Subject, n: int, capname: string, iname="") =
      let ck = CapKind(n)
      trace iname, "capopen " & $ck & " -> " & $ms.si
      push(ms.capStack, (cft: cftOpen, si: ms.si, ck: ck, name: capname))
      inc ms.ip

    template opCapCloseFn(ms: MatchState, s: Subject, n: int, actionCode: untyped, iname="") =
      let ck = CapKind(n)
      trace iname, "capclose " & $ck & " -> " & $ms.si
      push(ms.capStack, (cft: cftClose, si: ms.si, ck: ck, name: ""))
      if ck == ckAction:
        let cs = fixCaptures(s, ms.capStack, FixOpen)
        let capture {.inject.} = collectCaptures(cs)
        block:
          actionCode
      elif ck == ckRef:
        let cs = fixCaptures(s, ms.capStack, FixOpen)
        let r = collectCapturesRef(cs)
        ms.refs[r.key] = r.val
      inc ms.ip

    proc opBackrefFn(ms: var MatchState, s: Subject, refName: string, iname="") =
      if refName in ms.refs:
        let s2 = ms.refs[refName]
        trace iname, "backref " & refName & ":\"" & s2 & "\""
        if subStrCmp(s, s.len, ms.si, s2):
          inc ms.ip
          inc ms.si, s2.len
        else:
          ms.ip = -1
      else:
        raise newException(NPegException, "Unknown back reference '" & refName & "'")

    template opReturnFn(ms: MatchState, s: Subject, iname="") =
      trace iname, "return"
      if ms.retStack.top == 0:
        trace iname, "done"
        result.ok = true
        break
      ms.ip = pop(ms.retStack)

    template opFailFn(ms: MatchState, s: Subject, iname="") =
      trace iname, "fail"
      if ms.backStack.top == 0:
        trace iname, "error"
        break
      (ms.ip, ms.si, ms.retStack.top, ms.capStack.top) = pop(ms.backStack)

    proc opErrFn(ms: var MatchState, s: Subject, msg: string, iname="") =
      trace iname, "err " & msg
      var e = newException(NPegException, "Parsing error at #" & $ms.si & ": expected \"" & msg & "\"")
      e.matchLen = ms.si
      e.matchMax = ms.simax
      raise e

    while true:

      # These cases will be filled in by genCode() which uses this template
      # as the match lambda boilerplate:

      cases

      # Keep track of the highest string index we ever reached, this is a good
      # indication of the location of errors when parsing fails

      if ms.si > ms.simax:
        ms.simax = ms.si

    # When the parsing machine is done, close the capture stack and collect all
    # the captures in the match result

    result.matchLen = ms.si
    result.matchMax = ms.simax
    if result.ok and ms.capStack.top > 0:
      result.cs = fixCaptures(s, ms.capStack, FixAll)

  {.pop.}

  Parser[T](fn: match)


# Convert the list of parser instructions into a Nim finite state machine

proc genCode*(patt: Patt, T: NimNode): NimNode =

  let msNode = ident("ms")
  let sNode = ident("s")

  var cases = quote do:
    case ms.ip

  for n, i in patt.pairs:

    let call = nnkCall.newTree(ident($i.op & "Fn"))
    call.add msNode
    call.add sNode

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

  cases.add nnkElse.newTree(parseStmt("opFailFn(ms, s)"))
  result = getAst skel(T, cases, msNode, sNode, ident "userdata", ident "capture")

  when false:
    echo result.repr


