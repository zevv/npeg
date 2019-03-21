
import macros
import strutils

import npeg/common
import npeg/patt
import npeg/stack


type

  RetFrame = int

  BackFrame = tuple
    ip: int
    si: int
    rp: int
    cp: int


# Template for generating the parsing match proc.  A dummy 'ip' node is passed
# into this template to prevent its name from getting mangled so that the code
# in the `peg` macro can access it

template skel(cases: untyped, ip: NimNode, c: NimNode) =

  {.push hint[XDeclaredButNotUsed]: off.}

  let match = proc(s: string): MatchResult =

    var
      ip: int
      si: int
      retStack: Stack[RetFrame]
      capStack: Stack[CapFrame]
      backStack: Stack[BackFrame]

    # Debug trace. Slow and expensive

    proc doTrace(msg: string) =
      var l = align($ip, 3) &
           " | " & align($si, 3) &
           " |" & alignLeft(dumpString(s, si, 24), 24) &
           "| " & alignLeft(msg, 30) &
           "| " & alignLeft(repeat("*", backStack.top), 20)
      if backStack.top > 0:
        l.add $backStack[backStack.top-1]
      echo l

    template trace(msg: string) =
      when npegTrace:
        doTrace(msg)

    # Helper procs

    proc subStrCmp(s: string, si: int, s2: string): bool =
      if si > s.len - s2.len:
        return false
      for i in 0..<s2.len:
        if s[si+i] != s2[i]:
          return false
      return true

    proc subIStrCmp(s: string, si: int, s2: string): bool =
      if si > s.len - s2.len:
        return false
      for i in 0..<s2.len:
        if s[si+i].toLowerAscii != s2[i].toLowerAscii:
          return false
      return true

    # State machine instruction handlers

    template opStrFn(s2: string) =
      trace "str \"" & dumpString(s2) & "\""
      if subStrCmp(s, si, s2):
        inc ip
        inc si, s2.len
      else:
        ip = -1

    template opIStrFn(s2: string) =
      trace "str " & s2.dumpString
      if subIStrCmp(s, si, s2):
        inc ip
        inc si, s2.len
      else:
        ip = -1

    template opSetFn(cs: CharSet) =
      trace "set " & dumpSet(cs)
      if si < s.len and s[si] in cs:
        inc ip
        inc si
      else:
        ip = -1

    template opSpanFn(cs: CharSet) =
      trace "span " & dumpSet(cs)
      while si < s.len and s[si] in cs:
        inc si
      inc ip

    template opNopFn() =
      trace "nop"
      inc ip

    template opAnyFn() =
      trace "any"
      if si < s.len:
        inc ip
        inc si
      else:
        ip = -1

    template opChoiceFn(n: int) =
      trace "choice -> " & $n
      backStack.push (ip:n, si:si, rp:retStack.top, cp:capStack.top)
      inc ip

    template opCommitFn(n: int) =
      trace "commit -> " & $n
      discard backStack.pop()
      ip = n

    template opPartCommitFn(n: int) =
      trace "pcommit -> " & $n
      backStack.update(si, si)
      backStack.update(cp, capStack.top)
      ip = n

    template opCallFn(label: string, address: int) =
      trace "call -> " & label & ":" & $address
      retStack.push ip+1
      ip = address

    template opJumpFn(label: string, address: int) =
      trace "jump -> " & label & ":" & $address
      ip = address

    template opCapOpenFn(n: int, name2: string) =
      let ck = CapKind(n)
      trace "capopen " & $ck & " -> " & $si
      capStack.push (cft: cftOpen, si: si, ck: ck, name: name2)
      inc ip
    
    template opCapCloseFn(n: int, name2: string, actionCode: untyped) =
      let ck = CapKind(n)
      trace "capclose " & $ck & " -> " & $si
      capStack.push (cft: cftClose, si: si, ck: ck, name: name2)
      if ck == ckAction:
        var mr: MatchResult
        collectCaptures(s, true, capStack, mr)
        block:
          let c {.inject.} = mr.captures
          actionCode
      inc ip

    template opReturnFn() =
      trace "return"
      if retStack.top == 0:
        trace "done"
        result.ok = true
        break
      ip = retStack.pop()

    template opFailFn() =
      if backStack.top == 0:
        trace "error"
        break
      (ip, si, retStack.top, capStack.top) = backStack.pop()
      trace "fail -> " & $ip

    template opErrFn(msg: string) =
      trace "err " & msg
      raise newException(NPegException, "Parsing error at #" & $si & ": expected " & msg)

    while true:

      # These cases will be filled in by genCode() which uses this template
      # as the match lambda boilerplate:

      cases

      # Keep track of the highest string index we ever reached, this is a good
      # indication of the location of errors when parsing fails

      result.matchLen = max(result.matchLen, si)

    # When the parsing machine is done, close the capture stack and collect all
    # the captures in the match result

    if result.ok and capStack.top > 0:
      collectCaptures(s, false, capStack, result)

  {.pop.}

  match


# Convert the list of parser instructions into a Nim finite state machine

proc genCode*(name: string, program: Patt): NimNode =

  let ipNode = ident("ip")
  let nopStmt = nnkStmtList.newTree(nnkDiscardStmt.newTree(newEmptyNode()))
  var cases = nnkCaseStmt.newTree(ipNode)

  for n, i in program.pairs:
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
        call.add newIntLitNode(i.callAddr)
      of opCapOpen:
        call.add newIntLitNode(i.capKind.int)
        call.add newStrLitNode(i.capName)
      of opCapClose:
        call.add newIntLitNode(i.capKind.int)
        call.add newStrLitNode(i.capName)
        if i.capAction != nil:
          call.add nnkStmtList.newTree(i.capAction)
        else:
          call.add nopStmt
      of opErr:
        call.add newStrLitNode(i.msg)
      of opReturn, opAny, opNop, opFail:
        discard
    cases.add nnkOfBranch.newTree(newLit(n), call)

  cases.add nnkElse.newTree(parseStmt("opFailFn()"))

  result = getAst skel(cases, ipNode, ident "c")
  when false:
    echo result.repr


