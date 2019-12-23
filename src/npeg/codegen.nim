
import macros
import strutils
import tables
import npeg/[common,patt,stack,capture]
when npegProfile:
  import math
  import times

type

  RetFrame = int

  BackFrame = object
    ip*: int # Instruction pointer
    si*: int # Subject index
    rp*: int # Retstack top pointer
    cp*: int # Capstack top pointer
    pp*: int # PrecStack top pointer

  PrecFrame = int

  MatchResult*[S] = object
    ok*: bool
    matchLen*: int
    matchMax*: int
    cs*: Captures[S]

  MatchState*[S] = object
    ip*: int
    si*: int
    simax*: int
    refs*: Table[string, string]
    retStack*: Stack[RetFrame]
    capStack*: Stack[CapFrame[S]]
    backStack*: Stack[BackFrame]
    precStack*: Stack[PrecFrame]

  Parser*[S, T] = object
    fn*: proc(ms: var MatchState[S], s: openArray[S], u: var T): MatchResult[S]


# This macro translates `$1`.. into `capture[1].s`.. and `@1` into `capture[1].si` 
# for use in code block captures. The source nimnode lineinfo is recursively
# copied to the newly genreated node to make sure "Capture out of range"
# exceptions are properly traced.

proc rewriteCodeBlock(n: NimNode): NimNode =
  proc cli(n2: NimNode) =
    n2.copyLineInfo(n)
    for nc in n2: cli(nc)
  if n.kind == nnkPrefix and n[0].kind == nnkIdent and n[1].kind == nnkIntLit:
    if n[0].eqIdent("$"):
      result = newDotExpr(nnkBracketExpr.newTree(ident("capture"), n[1]), ident("s"))
    elif n[0].eqIdent("@"):
      result = newDotExpr(nnkBracketExpr.newTree(ident("capture"), n[1]), ident("si"))
    cli(result)
  elif n.kind == nnkNilLit:
    result = quote do:
      discard
  else:
    result = copyNimNode(n)
    for nc in n:
      result.add rewriteCodeBlock(nc)


proc initMatchState*[S](): MatchState[S] =
  result = MatchState[S](
    retStack: initStack[RetFrame]("return", 8, npegRetStackSize),
    capStack: initStack[CapFrame[S]]("capture", 8),
    backStack: initStack[BackFrame]("backtrace", 8, npegBackStackSize),
    precStack: initStack[PrecFrame]("precedence", 8, 16),
  )
  push(result.precStack, 0)


# This is a variant of the main 'cases' loop with extensive profileing of
# time spent, instruction count and fail count. Slow.

proc genProfileCode*(listing: seq[string], count: int, ms, s, si, simax, ip, cases: NimNode): NimNode =

  result = quote do:
    var tInst: array[0..`count`, float]
    var nInst: array[0..`count`, int]
    var nFail: array[0..`count`, int]
    var tTotal: float
    var nTotal: int
    var nTotalFail: int

    while true:
      let ipProf = `ip`
      let t1 = cpuTime()

      `cases`

      let dt = cpuTime() - t1
      nInst[ipProf] += 1
      tInst[ipProf] += dt
      if `ip` == `count`:
        nFail[ipProf] += 1
        nTotalFail += 1
      tTotal += dt
      nTotal += 1

    # Dump profiling results

    let tMax = sqrt(max(tInst))
    if tMax > 0:
      for i, l in `listing`:
        let graph = strutils.align(repeat("#", (int)(5.0*sqrt(tInst[i])/tMax)), 5)
        let perc = formatFloat(100.0 * tInst[i] / tTotal, ffDecimal, 1)
        echo graph,
             " ",   strutils.align(perc, 5),
             " | ", strutils.align($nInst[i], 6),
             " | ", strutils.align($nFail[i], 6),
             " | ", strutils.align($i, 3),
             ": ",  l
    echo ""
    echo "Total instructions : ", nTotal
    echo "Total fails        : ", nTotalFail
  
# Generate out all the case handlers for the parser program

proc genCasesCode*(program: Program, sType, uType, uId: NimNode, ms, s, si, simax, ip: NimNode): NimNode =
  
  result = quote do:
    case `ip`

  for ipNow, i in program.patt.pairs:

    let
      ipNext = ipNow + 1
      opName = newLit(repeat(" ", i.indent) & ($i.op).toLowerAscii[2..^1])
      iname = newLit(i.name)
      ipFail = if i.failOffset == 0:
        program.patt.high
      else:
        ipNow + i.failOffset

    var call = case i.op:

      of opChr:
        let ch = newLit(i.ch)
        quote do:
          trace `ms`, `iname`, `opName`, `s`, "\"" & escapeChar(`ch`) & "\""
          if `si` < `s`.len and `s`[`si`] == `ch`.char:
            inc `si`
            `ip` = `ipNext`
          else:
            `ip` = `ipFail`

      of opLit:
        let lit = i.lit
        quote do:
          trace `ms`, `iname`, `opName`, `s`, `lit`.repr
          if `si` < `s`.len and `s`[`si`] == `lit`:
            inc `si`
            `ip` = `ipNext`
          else:
            `ip` = `ipFail`

      of opSet:
        let cs = newLit(i.cs)
        quote do:
          trace `ms`, `iname`, `opName`, `s`, dumpSet(`cs`)
          if `si` < `s`.len and `s`[`si`] in `cs`:
            inc `si`
            `ip` = `ipNext`
          else:
            `ip` = `ipFail`

      of opSpan:
        let cs = newLit(i.cs)
        quote do:
          trace `ms`, `iname`, `opName`, `s`, dumpSet(`cs`)
          while `si` < `s`.len and `s`[`si`] in `cs`:
            inc `si`
          `ip` = `ipNext`

      of opChoice:
        let ip2 = newLit(ipNow + i.ipOffset)
        let siOffset = newLit(i.siOffset)
        quote do:
          trace `ms`, `iname`, `opName`, `s`, $`ip2`
          push(`ms`.backStack, BackFrame(ip:`ip2`, si:`si`+`siOffset`, rp:`ms`.retStack.top, cp:`ms`.capStack.top, pp:`ms`.precStack.top))
          `ip` = `ipNext`

      of opCommit:
        let ip2 = newLit(ipNow + i.ipOffset)
        quote do:
          trace `ms`, `iname`, `opName`, `s`, $`ip2`
          discard pop(`ms`.backStack)
          `ip` = `ip2`

      of opCall:
        let label = newLit(i.callLabel)
        let ip2 = newLit(ipNow + i.callOffset)
        quote do:
          trace `ms`, `iname`, `opName`, `s`, `label` & ":" & $`ip2`
          push(`ms`.retStack, `ip`+1)
          `ip` = `ip2`

      of opJump:
        let label = newLit(i.callLabel)
        let ip2 = newLit(ipNow + i.callOffset)
        quote do:
          trace `ms`, `iname`, `opName`, `s`, `label` & ":" & $`ip2`
          `ip` = `ip2`

      of opCapOpen:
        let capKind = newLit(i.capKind)
        let capName = newLit(i.capName)
        let capSiOffset = newLit(i.capSiOffset)
        quote do:
          trace `ms`, `iname`, `opName`, `s`, $`capKind` & " -> " & $`si`
          push(`ms`.capStack, CapFrame[`sType`](cft: cftOpen, si: `si`+`capSiOffset`, ck: `capKind`, name: `capName`))
          `ip` = `ipNext`

      of opCapClose:
        let ck = newLit(i.capKind)

        case i.capKind:
          of ckAction:
            let code = rewriteCodeBlock(i.capAction)
            quote do:
              trace `ms`, `iname`, `opName`, `s`, "ckAction -> " & $`si`
              push(`ms`.capStack, CapFrame[`sType`](cft: cftClose, si: `si`, ck: `ck`))
              let capture {.inject.} = collectCaptures(fixCaptures[`sType`](`s`, `ms`.capStack, FixOpen))
              var ok = true
              template validate(o: bool) = ok = o
              template fail() = ok = false
              template push(`s`: string) =
                push(`ms`.capStack, CapFrame[`sType`](cft: cftOpen, ck: ckStr))
                push(`ms`.capStack, CapFrame[`sType`](cft: cftClose, ck: ckStr, sPushed: `s`))
              block:
                `code`
              if ok:
                `ip` = `ipNext`
              else:
                `ip` = `ipFail`

          of ckRef:
            quote do:
              trace `ms`, `iname`, `opName`, `s`, "ckRef -> " & $`si`
              push(`ms`.capStack, CapFrame[`sType`](cft: cftClose, si: `si`, ck: `ck`))
              let r = collectCapturesRef(fixCaptures[`sType`](`s`, `ms`.capStack, FixOpen))
              `ms`.refs[r.key] = r.val
              `ip` = `ipNext`

          else:
            quote do:
              trace `ms`, `iname`, `opName`, `s`, $`ck` & " -> " & $`si`
              push(`ms`.capStack, CapFrame[`sType`](cft: cftClose, si: `si`, ck: `ck`))
              `ip` = `ipNext`

      of opBackRef:
        let refName = newLit(i.refName)
        quote do:
          if `refName` in `ms`.refs:
            let s2 = `ms`.refs[`refName`]
            trace `ms`, `iname`, `opName`, `s`, `refName` & ":\"" & s2 & "\""
            if subStrCmp(`s`, `s`.len, `si`, s2):
              inc `si`, s2.len
              `ip` = `ipNext`
            else:
              `ip` = `ipFail`
          else:
            raise newException(NPegException, "Unknown back reference '" & `refName` & "'")

      of opErr:
        let msg = newLit(i.msg)
        quote do:
          trace `ms`, `iname`, `opName`, `s`, `msg`
          var e = newException(NPegException, "Parsing error at #" & $`si` & ": expected \"" & `msg` & "\"")
          `simax` = max(`simax`, `si`)
          e.matchLen = `si`
          e.matchMax = `simax`
          raise e

      of opReturn:
        quote do:
          if `ms`.retStack.top > 0:
            trace `ms`, `iname`, `opName`, `s`
            `ip` = pop(`ms`.retStack)
          else:
            trace `ms`, `iname`, `opName`, `s`
            result.ok = true
            `simax` = max(`simax`, `si`)
            break

      of opAny:
        quote do:
          trace `ms`, `iname`, `opName`, `s`
          if `si` < `s`.len:
            inc `si`
            `ip` = `ipNext`
          else:
            `ip` = `ipFail`

      of opNop:
        quote do:
          trace `ms`, `iname`, `opName`, `s`
          `ip` = `ipNext`

      of opPrecPush:
        if i.prec == 0:
          quote do:
            push(`ms`.precStack, 0)
            `ip` = `ipNext`
        else:
          let (iPrec, iAssoc) = (i.prec.newLit, i.assoc.newLit)
          if i.assoc == assocLeft:
            quote do:
              if peek(`ms`.precStack) < `iPrec`:
                push(`ms`.precStack, `iPrec`)
                `ip` = `ipNext`
              else:
                `ip` = `ipFail`
          else:
            quote do:
              if peek(`ms`.precStack) <= `iPrec`:
                push(`ms`.precStack, `iPrec`)
                `ip` = `ipNext`
              else:
                `ip` = `ipFail`

      of opPrecPop:
        quote do:
            discard `ms`.precStack.pop()
            `ip` = `ipNext`

      of opFail:
        quote do:
          `simax` = max(`simax`, `si`)
          if `ms`.backStack.top > 0:
            trace `ms`, "", "opFail", `s`, "(backtrack)"
            let t = pop(`ms`.backStack)
            (`ip`, `si`, `ms`.retStack.top, `ms`.capStack.top, `ms`.precStack.top) = (t.ip, t.si, t.rp, t.cp, t.pp)
          else:
            trace `ms`, "", "opFail", `s`, "(error)"
            break

    result.add nnkOfBranch.newTree(newLit(ipNow), call)


# Generate code for tracing the parser. An empty stub is generated if tracing
# is disabled

proc genTraceCode*(program: Program, sType, uType, uId, ms, s, si, simax, ip: NimNode): NimNode =
  
  when npegTrace:
    result = quote do:
      proc doTrace(`ms`: var MatchState, iname, opname: string, `s`: openArray[`sType`], msg: string) =
          echo align(if `ip` >= 0: $`ip` else: "", 3) &
            "|" & align($(peek(`ms`.precStack)), 3) &
            "|" & align($`si`, 3) &
            "|" & alignLeft(dumpSubject(`s`, `si`, 24), 24) &
            "|" & alignLeft(iname, 15) &
            "|" & alignLeft(opname & " " & msg, 40) &
            "|" & repeat("*", `ms`.backStack.top)

      template trace(`ms`: var MatchState, iname, opname: string, `s`: openArray[`sType`], msg = "") =
        doTrace(`ms`, iname, opname, `s`, msg)

  else:
    result = quote do:
      template trace(`ms`: var MatchState, iname, opname: string, `s`: openArray[`sType`], msg = "") =
        discard

# Convert the list of parser instructions into a Nim finite state machine
# 
# - sType is the base type of the subject; typically `char` but can be specified
#   to be another type by the user
# - uType is the type of the userdata, if not used this defaults to `bool`
# - uId is the identifier of the userdata, if not used this defaults to `userdata`

proc genCode*(program: Program, sType, uType, uId: NimNode): NimNode =

  let
    count = program.patt.high
    suffix = "_NP"
    ms = ident "ms" & suffix
    s = ident "s" & suffix
    si = ident "si" & suffix
    ip = ident "ip" & suffix
    simax = ident "simax" & suffix

    casesCode = genCasesCode(program, sType, uType, uId, ms, s, si, simax, ip)
    traceCode = genTraceCode(program, sType, uType, uId, ms, s, si, simax, ip)

  # Generate the parser main loop. The .computedGoto.
  # pragma will generate code using C computed gotos, which will get highly
  # optmized, mostly eliminating the inner parser loop

  when npegProfile:
    let loopCode = genProfileCode(program.listing, count, ms, s, si, simax, ip, casesCode)
  else:
    let loopCode = quote do:
      while true:
        {.computedGoto.}
        `casesCode`

  # This is the result of genCode: a Parser object with a pointer to the
  # generated proc below doing the matching.

  result = quote do:

    proc fn(`ms`: var MatchState, `s`: openArray[`sType`], `uId`: var `uType`): MatchResult {.gensym.} =

      # Create local instances of performance-critical MatchState vars, this saves a
      # dereference on each access

      var
        `ip`: range[0..`count`] = `ms`.ip
        `si` = `ms`.si
        `simax` = `ms`.simax

      `traceCode`

      {.push hint[XDeclaredButNotUsed]: off.}
      `loopCode`
      {.pop.}

      # When the parsing machine is done, copy the local copies of the matchstate
      # back, close the capture stack and collect all the captures in the match
      # result

      `ms`.ip = `ip`
      `ms`.si = `si`
      `ms`.simax = `simax`
      result.matchLen = `ms`.si
      result.matchMax = `ms`.simax
      if result.ok and `ms`.capStack.top > 0:
        result.cs = fixCaptures(`s`, `ms`.capStack, FixAll)

    Parser[`sType`,`uType`](fn: fn)

  when npegExpand:
    echo result.repr

