
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

template skel(T: untyped, cases: untyped, ms: NimNode, s: NimNode, userdata: NimNode, capture: NimNode) =

  {.push hint[XDeclaredButNotUsed]: off.}

  let match = proc(ms: var MatchState, s: Subject, userdata: var T): MatchResult =

    # Debug trace. Slow and expensive

    proc doTrace(iname: string, ms: var MatchState, s: Subject, msg: string) =
      echo align(if ms.ip >= 0: $ms.ip else: "", 3) &
        "|" & align($ms.si, 3) &
        "|" & alignLeft(dumpString(s, ms.si, 24), 24) &
        "|" & alignLeft(iname, 15) &
        "|" & alignLeft(msg, 30) &
        "|" & alignLeft(repeat("*", ms.backStack.top), 20) 

    template trace(iname: string, ms: var MatchState, s: Subject, msg: string) =
      when npegTrace:
        doTrace(iname, ms, s, msg)

    # Parser main loop. `cases` will be filled in by genCode() which uses this template
    # as the match lambda boilerplate:

    while true:
      cases

      # Keep track of the highest string index we ever reached, this is a good
      # indication of the location of errors when parsing fails

      ms.simax = max(ms.simax, ms.si)

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

  var cases = quote do:
    case ms.ip

  for n, i in patt.pairs:

    var call = case i.op:

      of opChr:
        let ch = newLit(i.ch)
        quote do:
          trace "Chr", ms, s, "chr \"" & escapeChar(`ch`) & "\""
          if ms.si < s.len and s[ms.si] == `ch`.char:
            inc ms.ip
            inc ms.si
          else:
            ms.ip = -1

      of opIChr:
        let ch = newLit(i.ch)
        quote do:
          trace "IChr", ms, s, "chr \"" & escapeChar(`ch`) & "\""
          if ms.si < s.len and s[ms.si].toLowerAscii == `ch`.char:
            inc ms.ip
            inc ms.si
          else:
            ms.ip = -1

      of opSet:
        let cs = newLit(i.cs)
        quote do:
          var cs: set[char]
          trace "Set", ms, s, "set " & dumpSet(`cs`)
          if ms.si < s.len and s[ms.si] in `cs`:
            inc ms.ip
            inc ms.si
          else:
            ms.ip = -1

      of opSpan:
        let cs = newLit(i.cs)
        quote do:
          trace "Span", ms, s, "span " & dumpSet(`cs`)
          while ms.si < s.len and s[ms.si] in `cs`:
            inc ms.si
          inc ms.ip

      of opChoice:
        let ip = newLit(n + i.offset)
        quote do:
          trace "Choice", ms, s, "choice -> " & $`ip`
          push(ms.backStack, (ip:`ip`, si:ms.si, rp:ms.retStack.top, cp:ms.capStack.top))
          inc ms.ip

      of opCommit:
        let ip = newLit(n + i.offset)
        quote do:
          trace "Commit", ms, s, "commit -> " & $`ip`
          discard pop(ms.backStack)
          ms.ip = `ip`

      of opPartCommit:
        let ip = newLit(n + i.offset)
        quote do:
          trace "PCommit", ms, s, "pcommit -> " & $`ip`
          update(ms.backStack, si, ms.si)
          update(ms.backStack, cp, ms.capStack.top)
          ms.ip = `ip`

      of opCall:
        let label = newLit(i.callLabel)
        let offset = newLit(i.callOffset)
        quote do:
          trace "Call", ms, s, "call -> " & `label` & ":" & $(ms.ip+`offset`)
          push(ms.retStack, ms.ip+1)
          ms.ip += `offset`

      of opJump:
        let label = newLit(i.callLabel)
        let offset = newLit(i.callOffset)
        quote do:
          trace "Jump", ms, s, "jump -> " & `label` & ":" & $(ms.ip+`offset`)
          ms.ip += `offset`

      of opCapOpen:
        let capKind = newLit(i.capKind)
        let capName = newLit(i.capName)
        quote do:
          trace "CapOpen", ms, s, "capopen " & $`capKind` & " -> " & $ms.si
          push(ms.capStack, (cft: cftOpen, si: ms.si, ck: `capKind`, name: `capName`))
          inc ms.ip

      of opCapClose:
        let ck = newLit(i.capKind)

        case i.capKind:
          of ckAction:
            let code = mkDollarCaptures(i.capAction)
            quote do:
              trace "CapClose", ms, s, "capclose ckAction -> " & $ms.si
              push(ms.capStack, (cft: cftClose, si: ms.si, ck: `ck`, name: ""))
              let capture {.inject.} = collectCaptures(fixCaptures(s, ms.capStack, FixOpen))
              var ok = true
              template assume(o: bool) = ok = o
              block:
                `code`
              if ok:
                inc ms.ip
              else:
                ms.ip = -1

          of ckRef:
            quote do:
              trace "CapClose", ms, s, "capclose ckRef -> " & $ms.si
              push(ms.capStack, (cft: cftClose, si: ms.si, ck: `ck`, name: ""))
              let r = collectCapturesRef(fixCaptures(s, ms.capStack, FixOpen))
              ms.refs[r.key] = r.val
              inc ms.ip

          else:
            quote do:
              trace "CapClose", ms, s, "capclose " & $`ck` & " -> " & $ms.si
              push(ms.capStack, (cft: cftClose, si: ms.si, ck: `ck`, name: ""))
              inc ms.ip

      of opBackRef:
        let refName = newLit(i.refName)
        quote do:
          if `refName` in ms.refs:
            let s2 = ms.refs[`refName`]
            trace "BackRef", ms, s, "backref " & `refName` & ":\"" & s2 & "\""
            if subStrCmp(s, s.len, ms.si, s2):
              inc ms.ip
              inc ms.si, s2.len
            else:
              ms.ip = -1
          else:
            raise newException(NPegException, "Unknown back reference '" & `refName` & "'")

      of opErr:
        let msg = newLit(i.msg)
        quote do:
          trace "Err", ms, s, "err " & `msg`
          var e = newException(NPegException, "Parsing error at #" & $ms.si & ": expected \"" & `msg` & "\"")
          e.matchLen = ms.si
          e.matchMax = ms.simax
          raise e

      of opReturn:
        quote do:
          trace "Return", ms, s, "return"
          if ms.retStack.top == 0:
            trace "Return", ms, s, "done"
            result.ok = true
            break
          ms.ip = pop(ms.retStack)

      of opAny:
        quote do:
          trace "Any", ms, s, "any"
          if ms.si < s.len:
            inc ms.ip
            inc ms.si
          else:
            ms.ip = -1

      of opNop:
        quote do:
          trace "Nop", ms, s, "nop"
          inc ms.ip

      of opFail:
        quote do:
          trace "Fail", ms, s, "fail"
          if ms.backStack.top == 0:
            trace "Fail", ms, s, "error"
            break
          (ms.ip, ms.si, ms.retStack.top, ms.capStack.top) = pop(ms.backStack)

    cases.add nnkOfBranch.newTree(newLit(n), call)

  cases.add nnkElse.newTree quote do:
    trace "Fail", ms, s, "fail"
    if ms.backStack.top == 0:
      trace "Fail", ms, s, "error"
      break
    (ms.ip, ms.si, ms.retStack.top, ms.capStack.top) = pop(ms.backStack)

  result = getAst skel(T, cases, ident "ms", ident "s", ident "userdata", ident "capture")

  when npegExpand:
    echo result.repr


