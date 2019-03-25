
import macros
import strutils

import npeg/common
import npeg/patt
import npeg/stack
import npeg/capture

const
  RETSTACK_MAX = 1024
  BACKSTACK_MAX = 1024

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



# Template for generating the parsing match proc.
#
# Note: Dummy 'ip' and 'c' nodes are passed into this template to prevent these
# names from getting mangled so that the code in the `peg` macro can access it.
# I'd love to hear if there are better solutions for this.

template skel(cases: untyped, ip: NimNode, c: NimNode) =

  {.push hint[XDeclaredButNotUsed]: off.}

  let match = proc(s: string): MatchResult =

    # The parser state

    var
      ip: int
      si: int
      retStack = initStack[RetFrame]("return", 8, RETSTACK_MAX)
      capStack = initStack[CapFrame]("capture", 8)
      backStack = initStack[BackFrame]("backtrace", 8, BACKSTACK_MAX)

    # Debug trace. Slow and expensive

    proc doTrace(iname, msg: string) =
      var l: string
      l.add if ip >= 0: align($ip, 3) else: "   "
      l.add "|" & align($si, 3)
      l.add "|" & alignLeft(dumpString(s, si, 24), 24)
      l.add "|" & alignLeft(iname, 15)
      l.add "|" & alignLeft(msg, 30)
      l.add "|" & alignLeft(repeat("*", backStack.top), 20)
      echo l

    template trace(iname, msg: string) =
      when npegTrace:
        doTrace(iname, msg)

    # State machine instruction handlers

    template opStrFn(s2: string, iname="") =
      trace iname, "str \"" & dumpString(s2) & "\""
      if subStrCmp(s, si, s2):
        inc ip
        inc si, s2.len
      else:
        ip = -1

    template opIStrFn(s2: string, iname="") =
      trace iname, "str " & s2.dumpString
      if subIStrCmp(s, si, s2):
        inc ip
        inc si, s2.len
      else:
        ip = -1

    template opSetFn(cs: CharSet, iname="") =
      trace iname, "set " & dumpSet(cs)
      if si < s.len and s[si] in cs:
        inc ip
        inc si
      else:
        ip = -1

    template opSpanFn(cs: CharSet, iname="") =
      trace iname, "span " & dumpSet(cs)
      while si < s.len and s[si] in cs:
        inc si
      inc ip

    template opNopFn(iname="") =
      trace iname, "nop"
      inc ip

    template opAnyFn(iname="") =
      trace iname, "any"
      if si < s.len:
        inc ip
        inc si
      else:
        ip = -1

    template opChoiceFn(n: int, iname="") =
      trace iname, "choice -> " & $n
      backStack.push (ip:n, si:si, rp:retStack.top, cp:capStack.top)
      inc ip

    template opCommitFn(n: int, iname="") =
      trace iname, "commit -> " & $n
      discard backStack.pop()
      ip = n

    template opPartCommitFn(n: int, iname="") =
      trace iname, "pcommit -> " & $n
      backStack.update(si, si)
      backStack.update(cp, capStack.top)
      ip = n

    template opCallFn(label: string, offset: int, iname="") =
      trace iname, "call -> " & label & ":" & $(ip+offset)
      retStack.push ip+1
      ip += offset

    template opJumpFn(label: string, offset: int, iname="") =
      trace iname, "jump -> " & label & ":" & $(ip+offset)
      ip += offset

    template opCapOpenFn(n: int, capname: string, iname="") =
      let ck = CapKind(n)
      trace iname, "capopen " & $ck & " -> " & $si
      capStack.push (cft: cftOpen, si: si, ck: ck, name: capname)
      inc ip
    
    template opCapCloseFn(n: int, actionCode: untyped, iname="") =
      let ck = CapKind(n)
      trace iname, "capclose " & $ck & " -> " & $si
      capStack.push (cft: cftClose, si: si, ck: ck, name: "")
      if ck == ckAction:
        let cs = fixCaptures(s, capStack, true)
        let c {.inject.} = collectCaptures(cs)
        block:
          actionCode
      inc ip

    template opReturnFn(iname="") =
      trace iname, "return"
      if retStack.top == 0:
        trace iname, "done"
        result.ok = true
        break
      ip = retStack.pop()

    template opFailFn(iname="") =
      trace iname, "fail"
      if backStack.top == 0:
        trace iname, "error"
        break
      (ip, si, retStack.top, capStack.top) = backStack.pop()

    template opErrFn(msg: string, iname="") =
      trace iname, "err " & msg
      raise newException(NPegException, "Parsing error at #" & $si & ": expected \"" & msg & "\"")

    while true:

      # These cases will be filled in by genCode() which uses this template
      # as the match lambda boilerplate:

      cases

      # Keep track of the highest string index we ever reached, this is a good
      # indication of the location of errors when parsing fails

      result.matchMax = max(result.matchMax, si)

    # When the parsing machine is done, close the capture stack and collect all
    # the captures in the match result

    result.matchLen = si
    if result.ok and capStack.top > 0:
      result.cs = fixCaptures(s, capStack, false)

  {.pop.}

  match


# Convert the list of parser instructions into a Nim finite state machine

proc genCode*(patt: Patt): NimNode =

  let ipNode = ident("ip")
  let nopStmt = nnkStmtList.newTree(nnkDiscardStmt.newTree(newEmptyNode()))
  var cases = nnkCaseStmt.newTree(ipNode)

  for n, i in patt.pairs:

    let call = nnkCall.newTree(ident($i.op & "Fn"))

    case i.op:
      of opStr, opIStr:
        call.add newStrLitNode(i.str)

      of opSet, opSpan:
        let setNode = nnkCurly.newTree()
        for c in i.cs: setNode.add newLit(c)
        call.add setNode

      of opChoice, opCommit, opPartCommit:
        call.add newIntLitNode(n + i.offset)

      of opCall, opJump:
        call.add newStrLitNode(i.callLabel)
        call.add newIntLitNode(i.callOffset)

      of opCapOpen:
        call.add newIntLitNode(i.capKind.int)
        call.add newStrLitNode(i.capName)

      of opCapClose:
        call.add newIntLitNode(i.capKind.int)
        if i.capAction != nil:
          call.add nnkStmtList.newTree(i.capAction)
        else:
          call.add nopStmt

      of opErr:
        call.add newStrLitNode(i.msg)

      of opReturn, opAny, opNop, opFail:
        discard

    when npegTrace:
      call.add newStrLitNode(i.name)

    cases.add nnkOfBranch.newTree(newLit(n), call)

  cases.add nnkElse.newTree(parseStmt("opFailFn()"))
  result = getAst skel(cases, ipNode, ident "c")

  when false:
    echo result.repr


