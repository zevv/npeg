
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
    charSets: Table[CharSet, int]


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


proc initMatchState*(): MatchState =
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

template skel(cases: untyped, ms: NimNode, s: NimNode, capture: NimNode,
              userDataType: untyped, userDataId: NimNode) =

  let match = proc(ms: var MatchState, s: Subject, userDataId: var userDataType): MatchResult =

    # Debug trace. Slow and expensive

    proc doTrace(ms: var MatchState, iname: string, s: Subject, msg: string) =
      when npegTrace:
        echo align(if ms.ip >= 0: $ms.ip else: "", 3) &
          "|" & align($ms.si, 3) &
          "|" & alignLeft(dumpString(s, ms.si, 24), 24) &
          "|" & alignLeft(iname, 15) &
          "|" & alignLeft(msg, 40) &
          "|" & repeat("*", ms.backStack.top)

    template trace(ms: var MatchState, iname: string, s: Subject, msg: string) =
      when npegTrace:
        doTrace(ms, iname, s, msg)

    # Create local instances of performance-critical MatchState vars, this saves a
    # dereference on each access

    var ip {.inject.} = ms.ip
    var si {.inject.} = ms.si
    var simax {.inject.} = ms.simax

    # Parser main loop. `cases` will be filled in by genCode() which uses this template
    # as the match lambda boilerplate:

    while true:
      {.push hint[XDeclaredButNotUsed]: off.}
      cases
      {.pop.}

    # When the parsing machine is done, copy the local copies of the matchstate
    # back, close the capture stack and collect all the captures in the match
    # result

    ms.ip = ip
    ms.si = si
    ms.simax = simax
    result.matchLen = ms.si
    result.matchMax = ms.simax
    if result.ok and ms.capStack.top > 0:
      result.cs = fixCaptures(s, ms.capStack, FixAll)

  Parser[userDataType](fn: match)


# Convert the list of parser instructions into a Nim finite state machine

proc genCode*(patt: Patt, userDataType: NimNode, userDataId: NimNode): NimNode =

  var cases = quote do:
    case ip
        

  for n, i in patt.pairs:

    when npegTrace:
      let iname = newLit(i.name)
    else:
      let iname = newLit ""

    var call = case i.op:

      of opChr:
        let ch = newLit(i.ch)
        quote do:
          trace ms, `iname`, s, "chr \"" & escapeChar(`ch`) & "\""
          if si < s.len and s[si] == `ch`.char:
            inc ip
            inc si
          else:
            ip = -1

      of opIChr:
        let ch = newLit(i.ch)
        quote do:
          trace ms, `iname`, s, "chr \"" & escapeChar(`ch`) & "\""
          if si < s.len and s[si].toLowerAscii == `ch`.char:
            inc ip
            inc si
          else:
            ip = -1

      of opStr:
        let s2 = newLit(i.str)
        quote do:
          trace ms, `iname`, s, "str \"" & dumpString(`s2`) & "\""
          if subStrCmp(s, s.len, si, `s2`):
            inc ip
            inc si, `s2`.len
          else:
            ip = -1

      of opIStr:
        let s2 = newLit(i.str)
        quote do:
          trace ms, `iname`, s, "str \"" & dumpString(`s2`) & "\""
          if subIStrCmp(s, s.len, si, `s2`):
            inc ip
            inc si, `s2`.len
          else:
            ip = -1

      of opSet:
        let cs = newLit(i.cs)
        quote do:
          trace ms, `iname`, s, "set " & dumpSet(`cs`)
          if si < s.len and s[si] in `cs`:
            inc ip
            inc si
          else:
            ip = -1

      of opSpan:
        let cs = newLit(i.cs)
        quote do:
          trace ms, `iname`, s, "span " & dumpSet(`cs`)
          while si < s.len and s[si] in `cs`:
            inc si
          inc ip

      of opChoice:
        let ip2 = newLit(n + i.offset)
        quote do:
          trace ms, `iname`, s, "choice -> " & $`ip2`
          push(ms.backStack, (ip:`ip2`, si:si, rp:ms.retStack.top, cp:ms.capStack.top))
          inc ip

      of opCommit:
        let ip2 = newLit(n + i.offset)
        quote do:
          trace ms, `iname`, s, "commit -> " & $`ip2`
          discard pop(ms.backStack)
          ip = `ip2`

      of opPartCommit:
        let ip2 = newLit(n + i.offset)
        quote do:
          trace ms, `iname`, s, "pcommit -> " & $`ip2`
          update(ms.backStack, si, si)
          update(ms.backStack, cp, ms.capStack.top)
          ip = `ip2`

      of opCall:
        let label = newLit(i.callLabel)
        let ip2 = newLit(n + i.callOffset)
        quote do:
          trace ms, `iname`, s, "call -> " & `label` & ":" & $`ip2`
          push(ms.retStack, ip+1)
          ip = `ip2`

      of opJump:
        let label = newLit(i.callLabel)
        let ip2 = newLit(n + i.callOffset)
        quote do:
          trace ms, `iname`, s, "jump -> " & `label` & ":" & $`ip2`
          ip = `ip2`

      of opCapOpen:
        let capKind = newLit(i.capKind)
        let capName = newLit(i.capName)
        quote do:
          trace ms, `iname`, s, "capopen " & $`capKind` & " -> " & $si
          push(ms.capStack, (cft: cftOpen, si: si, ck: `capKind`, name: `capName`))
          inc ip

      of opCapClose:
        let ck = newLit(i.capKind)

        case i.capKind:
          of ckAction:
            let code = mkDollarCaptures(i.capAction)
            quote do:
              trace ms, `iname`, s, "capclose ckAction -> " & $si
              push(ms.capStack, (cft: cftClose, si: si, ck: `ck`, name: ""))
              let capture {.inject.} = collectCaptures(fixCaptures(s, ms.capStack, FixOpen))
              var ok = true
              template validate(o: bool) = ok = o
              block:
                `code`
              if ok:
                inc ip
              else:
                ip = -1

          of ckRef:
            quote do:
              trace ms, `iname`, s, "capclose ckRef -> " & $si
              push(ms.capStack, (cft: cftClose, si: si, ck: `ck`, name: ""))
              let r = collectCapturesRef(fixCaptures(s, ms.capStack, FixOpen))
              ms.refs[r.key] = r.val
              inc ip

          else:
            quote do:
              trace ms, `iname`, s, "capclose " & $`ck` & " -> " & $si
              push(ms.capStack, (cft: cftClose, si: si, ck: `ck`, name: ""))
              inc ip

      of opBackRef:
        let refName = newLit(i.refName)
        quote do:
          if `refName` in ms.refs:
            let s2 = ms.refs[`refName`]
            trace ms, `iname`, s, "backref " & `refName` & ":\"" & s2 & "\""
            if subStrCmp(s, s.len, si, s2):
              inc ip
              inc si, s2.len
            else:
              ip = -1
          else:
            raise newException(NPegException, "Unknown back reference '" & `refName` & "'")

      of opErr:
        let msg = newLit(i.msg)
        quote do:
          trace ms, `iname`, s, "err " & `msg`
          var e = newException(NPegException, "Parsing error at #" & $si & ": expected \"" & `msg` & "\"")
          simax = max(simax, si)
          e.matchLen = si
          e.matchMax = simax
          raise e

      of opReturn:
        quote do:
          if ms.retStack.top > 0:
            trace ms, `iname`, s, "return"
            ip = pop(ms.retStack)
          else:
            trace ms, `iname`, s, "return (done)"
            result.ok = true
            simax = max(simax, si)
            break

      of opAny:
        quote do:
          trace ms, `iname`, s, "any"
          if si < s.len:
            inc ip
            inc si
          else:
            ip = -1

      of opNop:
        quote do:
          trace ms, `iname`, s, "nop"
          inc ip

      of opFail:
        quote do:
          if ms.backStack.top > 0:
            trace ms, `iname`, s, "fail (backtrace)"
          else:
            trace ms, `iname`, s, "fail (error)"
            simax = max(simax, si)
            break
          simax = max(simax, si)
          (ip, si, ms.retStack.top, ms.capStack.top) = pop(ms.backStack)

    cases.add nnkOfBranch.newTree(newLit(n), call)

  cases.add nnkElse.newTree quote do:
    simax = max(simax, si)
    if ms.backStack.top > 0:
      trace ms, "", s, "fail"
      (ip, si, ms.retStack.top, ms.capStack.top) = pop(ms.backStack)
    else:
      trace ms, "", s, "error"
      break

  result = getAst skel(cases, ident "ms", ident "s", ident "capture",
                       userDataType, userDataId)

  when npegExpand:
    echo result.repr


