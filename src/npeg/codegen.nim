
import macros
import strutils
import tables
import npeg/[common,patt,stack,capture]

type

  RetFrame = int

  BackFrame = object
    ip*: int # Instruction pointer
    si*: int # Subject index
    rp*: int # Retstack top pointer
    cp*: int # Capstack top pointer
    pp*: int # PrecStack top pointer

  PrecFrame = int

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
    precStack*: Stack[PrecFrame]

  Parser*[T] = object
    fn*: proc(ms: var MatchState, s: Subject, userdata: var T): MatchResult
    charSets: Table[CharSet, int]


# This macro translates `$1`.. into `capture[0]`.. for use in code block captures

proc mkDollarCaptures(n: NimNode): NimNode =
  if n.kind == nnkPrefix and
       n[0].kind == nnkIdent and n[0].eqIdent("$") and
       n[1].kind == nnkIntLit:
    let i = int(n[1].intVal)
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
    precStack: initStack[PrecFrame]("precedence", 8, 16),
  )
  push(result.precStack, 0)


# Template for generating the parsing match proc.
#
# Note: Dummy 'ms', 'userdata' and 'capture' nodes are passed into this
# template to prevent these names from getting mangled so that the code in the
# `peg` macro can access it.  I'd love to hear if there are better solutions
# for this.

template skel(cases: untyped, count: int, ms: NimNode, s: NimNode, capture: NimNode,
              userDataType: untyped, userDataId: NimNode) =

  let match = proc(ms: var MatchState, s: Subject, userDataId: var userDataType): MatchResult =

    # Create local instances of performance-critical MatchState vars, this saves a
    # dereference on each access

    var
      ip {.inject.}: range[0..count] = ms.ip
      si {.inject.} = ms.si
      simax {.inject.} = ms.simax

    # Debug trace. Slow and expensive

    proc doTrace(ms: var MatchState, iname, opname: string, s: Subject, msg: string) =
      when npegTrace:
        echo align(if ip >= 0: $ip else: "", 3) &
          "|" & align($(peek(ms.precStack)), 3) &
          "|" & align($si, 3) &
          "|" & alignLeft(dumpString(s, si, 24), 24) &
          "|" & alignLeft(iname, 15) &
          "|" & alignLeft(opname & " " & msg, 40) &
          "|" & repeat("*", ms.backStack.top)

    template trace(ms: var MatchState, iname, opname: string, s: Subject, msg = "") =
      when npegTrace:
        doTrace(ms, iname, opname, s, msg)

    # Parser main loop. `cases` will be filled in by genCode() which uses this
    # template as the match lambda boilerplate. The .computedGoto. pragma will
    # generate code using C computed gotos, which will get highly optmized,
    # mostly eliminating the inner parser loop

    while true:
      {.computedGoto.}
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

proc genCode*(program: Program, userDataType: NimNode, userDataId: NimNode): NimNode =

  var cases = quote do:
    case ip


  for ipNow, i in program.patt.pairs:

    let
      ipNext = ipNow + 1
      opName = newLit(($i.op).toLowerAscii[2..^1])
      iname = newLit(i.name)
      ipFail = if i.failOffset == 0:
        program.patt.high
      else:
        ipNow + i.failOffset

    var call = case i.op:

      of opChr:
        let ch = newLit(i.ch)
        quote do:
          trace ms, `iname`, `opName`, s, "\"" & escapeChar(`ch`) & "\""
          if si < s.len and s[si] == `ch`.char:
            inc si
            ip = `ipNext`
          else:
            ip = `ipFail`

      of opStr:
        let s2 = newLit(i.str)
        quote do:
          trace ms, `iname`, `opName`, s, "\"" & dumpString(`s2`) & "\""
          if subStrCmp(s, s.len, si, `s2`):
            inc si, `s2`.len
            ip = `ipNext`
          else:
            ip = `ipFail`

      of opIStr:
        let s2 = newLit(i.str)
        quote do:
          trace ms, `iname`, `opName`, s, "\"" & dumpString(`s2`) & "\""
          if subIStrCmp(s, s.len, si, `s2`):
            inc si, `s2`.len
            ip = `ipNext`
          else:
            ip = `ipFail`

      of opSet:
        let cs = newLit(i.cs)
        quote do:
          trace ms, `iname`, `opName`, s, dumpSet(`cs`)
          if si < s.len and s[si] in `cs`:
            inc si
            ip = `ipNext`
          else:
            ip = `ipFail`

      of opSpan:
        let cs = newLit(i.cs)
        quote do:
          trace ms, `iname`, `opName`, s, dumpSet(`cs`)
          while si < s.len and s[si] in `cs`:
            inc si
          ip = `ipNext`

      of opChoice:
        let ip2 = newLit(ipNow + i.ipOffset)
        let siOffset = newLit(i.siOffset)
        quote do:
          trace ms, `iname`, `opName`, s, $`ip2`
          push(ms.backStack, BackFrame(ip:`ip2`, si:si+`siOffset`, rp:ms.retStack.top, cp:ms.capStack.top, pp:ms.precStack.top))
          ip = `ipNext`

      of opCommit:
        let ip2 = newLit(ipNow + i.ipOffset)
        quote do:
          trace ms, `iname`, `opName`, s, $`ip2`
          discard pop(ms.backStack)
          ip = `ip2`

      of opCall:
        let label = newLit(i.callLabel)
        let ip2 = newLit(ipNow + i.callOffset)
        quote do:
          trace ms, `iname`, `opName`, s, `label` & ":" & $`ip2`
          push(ms.retStack, ip+1)
          ip = `ip2`

      of opJump:
        let label = newLit(i.callLabel)
        let ip2 = newLit(ipNow + i.callOffset)
        quote do:
          trace ms, `iname`, `opName`, s, `label` & ":" & $`ip2`
          ip = `ip2`

      of opCapOpen:
        let capKind = newLit(i.capKind)
        let capName = newLit(i.capName)
        let capSiOffset = newLit(i.capSiOffset)
        quote do:
          trace ms, `iname`, `opName`, s, $`capKind` & " -> " & $si
          push(ms.capStack, CapFrame(cft: cftOpen, si: si+`capSiOffset`, ck: `capKind`, name: `capName`))
          ip = `ipNext`

      of opCapClose:
        let ck = newLit(i.capKind)

        case i.capKind:
          of ckAction:
            let code = mkDollarCaptures(i.capAction)
            quote do:
              trace ms, `iname`, `opName`, s, "ckAction -> " & $si
              push(ms.capStack, CapFrame(cft: cftClose, si: si, ck: `ck`))
              let capture {.inject.} = collectCaptures(fixCaptures(s, ms.capStack, FixOpen))
              var ok = true
              template validate(o: bool) = ok = o
              template fail() = ok = false
              template push(s: string) =
                push(ms.capStack, CapFrame(cft: cftOpen, ck: ckStr))
                push(ms.capStack, CapFrame(cft: cftClose, ck: ckStr, sPushed: s))
              block:
                `code`
              if ok:
                ip = `ipNext`
              else:
                ip = `ipFail`

          of ckRef:
            quote do:
              trace ms, `iname`, `opName`, s, "ckRef -> " & $si
              push(ms.capStack, CapFrame(cft: cftClose, si: si, ck: `ck`))
              let r = collectCapturesRef(fixCaptures(s, ms.capStack, FixOpen))
              ms.refs[r.key] = r.val
              ip = `ipNext`

          else:
            quote do:
              trace ms, `iname`, `opName`, s, $`ck` & " -> " & $si
              push(ms.capStack, CapFrame(cft: cftClose, si: si, ck: `ck`))
              ip = `ipNext`

      of opBackRef:
        let refName = newLit(i.refName)
        quote do:
          if `refName` in ms.refs:
            let s2 = ms.refs[`refName`]
            trace ms, `iname`, `opName`, s, `refName` & ":\"" & s2 & "\""
            if subStrCmp(s, s.len, si, s2):
              inc si, s2.len
              ip = `ipNext`
            else:
              ip = `ipFail`
          else:
            raise newException(NPegException, "Unknown back reference '" & `refName` & "'")

      of opErr:
        let msg = newLit(i.msg)
        quote do:
          trace ms, `iname`, `opName`, s, `msg`
          var e = newException(NPegException, "Parsing error at #" & $si & ": expected \"" & `msg` & "\"")
          simax = max(simax, si)
          e.matchLen = si
          e.matchMax = simax
          raise e

      of opReturn:
        quote do:
          if ms.retStack.top > 0:
            trace ms, `iname`, `opName`, s
            ip = pop(ms.retStack)
          else:
            trace ms, `iname`, `opName`, s
            result.ok = true
            simax = max(simax, si)
            break

      of opAny:
        quote do:
          trace ms, `iname`, `opName`, s
          if si < s.len:
            inc si
            ip = `ipNext`
          else:
            ip = `ipFail`

      of opNop:
        quote do:
          trace ms, `iname`, `opName`, s
          ip = `ipNext`

      of opPrecPush:
        if i.prec == 0:
          quote do:
            push(ms.precStack, 0)
            ip = `ipNext`
        else:
          let (iPrec, iAssoc) = (i.prec.newLit, i.assoc.newLit)
          if i.assoc == assocLeft:
            quote do:
              if peek(ms.precStack) < `iPrec`:
                push(ms.precStack, `iPrec`)
                ip = `ipNext`
              else:
                ip = `ipFail`
          else:
            quote do:
              if peek(ms.precStack) <= `iPrec`:
                push(ms.precStack, `iPrec`)
                ip = `ipNext`
              else:
                ip = `ipFail`

      of opPrecPop:
        quote do:
            discard ms.precStack.pop()
            ip = `ipNext`

      of opFail:
        quote do:
          simax = max(simax, si)
          if ms.backStack.top > 0:
            trace ms, "", "opFail", s, "(backtrack)"
            let t = pop(ms.backStack)
            (ip, si, ms.retStack.top, ms.capStack.top, ms.precStack.top) = (t.ip, t.si, t.rp, t.cp, t.pp)
          else:
            trace ms, "", "opFail", s, "(error)"
            break

    cases.add nnkOfBranch.newTree(newLit(ipNow), call)

  result = getAst skel(cases, program.patt.high, ident "ms", ident "s", ident "capture",
                       userDataType, userDataId)

  when npegExpand:
    echo result.repr


