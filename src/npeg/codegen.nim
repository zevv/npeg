
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
    fn_init*: proc(): MatchState[S]
    when npegGcsafe:
      fn_run*: proc(ms: var MatchState[S], s: openArray[S], u: var T): MatchResult[S] {.gcsafe.}
    else:
      fn_run*: proc(ms: var MatchState[S], s: openArray[S], u: var T): MatchResult[S]


# This macro translates `$1`.. into `capture[1].s`.. and `@1` into `capture[1].si` 
# for use in code block captures. The source nimnode lineinfo is recursively
# copied to the newly genreated node to make sure "Capture out of range"
# exceptions are properly traced.

proc doSugar(n, captureId: NimNode): NimNode =
  proc cli(n2: NimNode) =
    n2.copyLineInfo(n)
    for nc in n2: cli(nc)
  let isIntPrefix =  n.kind == nnkPrefix and n[0].kind == nnkIdent and n[1].kind == nnkIntLit
  if isIntPrefix and n[0].eqIdent("$"):
    result = newDotExpr(nnkBracketExpr.newTree(captureId, n[1]), ident("s"))
    cli result
  elif isIntPrefix and n[0].eqIdent("@"):
    result = newDotExpr(nnkBracketExpr.newTree(captureId, n[1]), ident("si"))
    cli result
  else:
    result = copyNimNode(n)
    for nc in n:
      result.add doSugar(nc, captureId)


# Generate the parser main loop. The .computedGoto. pragma will generate code
# using C computed gotos, which will get highly optmized, mostly eliminating
# the inner parser loop. Nim limits computed goto to a maximum of 10_000
# cases; if our program is this large, emit a warning and do not use a
# computed goto

proc genLoopCode(program: Program, casesCode: NimNode): NimNode=
  result = nnkWhileStmt.newTree(true.newLit, nnkStmtList.newTree())
  if program.patt.len < 10_000:
    result[1].add nnkPragma.newTree("computedGoto".ident)
  else:
    warning "Grammar too large for computed goto, falling back to normal 'case'"
  result[1].add casesCode
  

# Generate out all the case handlers for the parser program

proc genCasesCode*(program: Program, sType, uType, uId: NimNode, ms, s, si, simax, ip: NimNode): NimNode =

  result = quote:
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
        quote:
          trace `ms`, `iname`, `opName`, `s`, "\"" & escapeChar(`ch`) & "\""
          if `si` < `s`.len and `s`[`si`] == `ch`.char:
            inc `si`
            `ip` = `ipNext`
          else:
            `ip` = `ipFail`

      of opLit:
        let lit = i.lit
        quote:
          trace `ms`, `iname`, `opName`, `s`, `lit`.repr
          if `si` < `s`.len and `s`[`si`] == `lit`:
            inc `si`
            `ip` = `ipNext`
          else:
            `ip` = `ipFail`

      of opSet:
        let cs = newLit(i.cs)
        quote:
          trace `ms`, `iname`, `opName`, `s`, dumpSet(`cs`)
          if `si` < `s`.len and `s`[`si`] in `cs`:
            inc `si`
            `ip` = `ipNext`
          else:
            `ip` = `ipFail`

      of opSpan:
        let cs = newLit(i.cs)
        quote:
          trace `ms`, `iname`, `opName`, `s`, dumpSet(`cs`)
          while `si` < `s`.len and `s`[`si`] in `cs`:
            inc `si`
          `ip` = `ipNext`

      of opChoice:
        let ip2 = newLit(ipNow + i.ipOffset)
        let siOffset = newLit(i.siOffset)
        quote:
          trace `ms`, `iname`, `opName`, `s`, $`ip2`
          push(`ms`.backStack, BackFrame(ip:`ip2`, si:`si`+`siOffset`, rp:`ms`.retStack.top, cp:`ms`.capStack.top, pp:`ms`.precStack.top))
          `ip` = `ipNext`

      of opCommit:
        let ip2 = newLit(ipNow + i.ipOffset)
        quote:
          trace `ms`, `iname`, `opName`, `s`, $`ip2`
          discard pop(`ms`.backStack)
          `ip` = `ip2`

      of opCall:
        let label = newLit(i.callLabel)
        let ip2 = newLit(ipNow + i.callOffset)
        quote:
          trace `ms`, `iname`, `opName`, `s`, `label` & ":" & $`ip2`
          push(`ms`.retStack, `ipNext`)
          `ip` = `ip2`

      of opJump:
        let label = newLit(i.callLabel)
        let ip2 = newLit(ipNow + i.callOffset)
        quote:
          trace `ms`, `iname`, `opName`, `s`, `label` & ":" & $`ip2`
          `ip` = `ip2`

      of opCapOpen:
        let capKind = newLit(i.capKind)
        let capName = newLit(i.capName)
        let capSiOffset = newLit(i.capSiOffset)
        quote:
          trace `ms`, `iname`, `opName`, `s`, $`capKind` & " -> " & $`si`
          push(`ms`.capStack, CapFrame[`sType`](cft: cftOpen, si: `si`+`capSiOffset`, ck: `capKind`, name: `capName`))
          `ip` = `ipNext`

      of opCapClose:
        let ck = newLit(i.capKind)

        case i.capKind:
          of ckAction:
            let captureId = ident "capture"
            let code = doSugar(i.capAction, captureId)
            quote:
              trace `ms`, `iname`, `opName`, `s`, "ckAction -> " & $`si`
              push(`ms`.capStack, CapFrame[`sType`](cft: cftClose, si: `si`, ck: `ck`))
              let capture = collectCaptures(fixCaptures[`sType`](`s`, `ms`.capStack, FixOpen))
              proc fn(`captureId`: Captures[`sType`], `ms`: var MatchState[`sType`], `uId`: var `uType`): bool =
                result = true
                `code`
              if fn(capture, `ms`, `uId`):
                `ip` = `ipNext`
              else:
                `ip` = `ipFail`

          of ckRef:
            quote:
              trace `ms`, `iname`, `opName`, `s`, "ckRef -> " & $`si`
              push(`ms`.capStack, CapFrame[`sType`](cft: cftClose, si: `si`, ck: `ck`))
              let r = collectCapturesRef(fixCaptures[`sType`](`s`, `ms`.capStack, FixOpen))
              `ms`.refs[r.key] = r.val
              `ip` = `ipNext`

          else:
            quote:
              trace `ms`, `iname`, `opName`, `s`, $`ck` & " -> " & $`si`
              push(`ms`.capStack, CapFrame[`sType`](cft: cftClose, si: `si`, ck: `ck`))
              `ip` = `ipNext`

      of opBackref:
        let refName = newLit(i.refName)
        quote:
          if `refName` in `ms`.refs:
            let s2 = `ms`.refs[`refName`]
            trace `ms`, `iname`, `opName`, `s`, `refName` & ":\"" & s2 & "\""
            if subStrCmp(`s`, `s`.len, `si`, s2):
              inc `si`, s2.len
              `ip` = `ipNext`
            else:
              `ip` = `ipFail`
          else:
            raise newException(NPegUnknownBackrefError, "Unknown back reference '" & `refName` & "'")

      of opErr:
        let msg = newLit(i.msg)
        quote:
          trace `ms`, `iname`, `opName`, `s`, `msg`
          var e = newException(NPegParseError, `msg`)
          `simax` = max(`simax`, `si`)
          raise e

      of opReturn:
        quote:
          trace `ms`, `iname`, `opName`, `s`
          if `ms`.retStack.top > 0:
            `ip` = pop(`ms`.retStack)
          else:
            result.ok = true
            `simax` = max(`simax`, `si`)
            break

      of opAny:
        quote:
          trace `ms`, `iname`, `opName`, `s`
          if `si` < `s`.len:
            inc `si`
            `ip` = `ipNext`
          else:
            `ip` = `ipFail`

      of opNop:
        quote:
          trace `ms`, `iname`, `opName`, `s`
          `ip` = `ipNext`

      of opPrecPush:
        if i.prec == 0:
          quote:
            push(`ms`.precStack, 0)
            `ip` = `ipNext`
        else:
          let (iPrec, iAssoc) = (i.prec.newLit, i.assoc.newLit)
          let exp = if i.assoc == assocLeft:
            quote: peek(`ms`.precStack) < `iPrec`
          else:
            quote: peek(`ms`.precStack) <= `iPrec`
          quote:
            if `exp`:
              push(`ms`.precStack, `iPrec`)
              `ip` = `ipNext`
            else:
              `ip` = `ipFail`

      of opPrecPop:
        quote:
            discard `ms`.precStack.pop()
            `ip` = `ipNext`

      of opFail:
        quote:
          `simax` = max(`simax`, `si`)
          if `ms`.backStack.top > 0:
            trace `ms`, "", "opFail", `s`, "(backtrack)"
            let t = pop(`ms`.backStack)
            (`ip`, `si`, `ms`.retStack.top, `ms`.capStack.top, `ms`.precStack.top) = (t.ip, t.si, t.rp, t.cp, t.pp)
          else:
            trace `ms`, "", "opFail", `s`, "(error)"
            break

    # Recursively copy the line info from the original instruction NimNode into
    # the generated Nim code
    proc aux(n: NimNode) =
      n.copyLineInfo(i.nimNode)
      for nc in n: aux(nc)
    aux(call)

    result.add nnkOfBranch.newTree(newLit(ipNow), call)


# Generate code for tracing the parser. An empty stub is generated if tracing
# is disabled

proc genTraceCode*(program: Program, sType, uType, uId, ms, s, si, simax, ip: NimNode): NimNode =
  
  when npegTrace:
    result = quote:
      proc doTrace[sType](`ms`: var MatchState, iname, opname: string, ip: int, s: openArray[sType], si: int, ms: var MatchState, msg: string) {.nimCall.} =
          echo align(if ip >= 0: $ip else: "", 3) &
            "|" & align($(peek(ms.precStack)), 3) &
            "|" & align($si, 3) &
            "|" & alignLeft(dumpSubject(s, si, 24), 24) &
            "|" & alignLeft(iname, 15) &
            "|" & alignLeft(opname & " " & msg, 40) &
            "|" & repeat("*", ms.backStack.top)

      template trace(`ms`: var MatchState, iname, opname: string, `s`: openArray[`sType`], msg = "") =
        doTrace(`ms`, iname, opname, `ip`, `s`, `si`, `ms`, msg)

  else:
    result = quote:
      template trace(`ms`: var MatchState, iname, opname: string, `s`: openArray[`sType`], msg = "") =
        discard


# Augment exception stack traces with the NPeg return stack and re-raise

proc genExceptionCode(ms, ip, si, simax, symTab: NimNode): NimNode =
  quote:

    # Helper proc to add a stack frame for the given ip
    var trace: seq[StackTraceEntry]
    let symTab = `symTab`
    proc aux(ip: int) =
      let sym = symTab[ip]
      trace.insert StackTraceEntry(procname: cstring(sym.repr), filename: cstring(sym.lineInfo.filename), line: sym.lineInfo.line)
      # On older Nim versions e.trace is not accessible, in this case just
      # dump the exception to stdout if npgStacktrace is enabled
      when npegStacktrace:
        echo $(sym.lineInfo) & ": " & sym.repr

    # Emit current IP and unwind all addresses from the return stack
    aux(`ip`)
    while `ms`.retStack.top > 0:
      aux(`ms`.retStack.pop())

    let e = getCurrentException()

    when compiles(e.trace.pop()):
      # drop the generated parser fn() from the trace and replace by the NPeg frames
      discard e.trace.pop()
      e.trace.add trace

    # Re-reaise the exception with the augmented stack trace and match index filled in
    if e of NPegException:
      let eref = (ref NPegException)(e)
      eref.matchLen = `si`
      eref.matchMax = `simax`
    raise


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
    loopCode = genLoopCode(program, casesCode)
    traceCode = genTraceCode(program, sType, uType, uId, ms, s, si, simax, ip)
    exceptionCode = genExceptionCode(ms, ip, si, simax, newLit(program.symTab))

  result = quote:

    proc fn_init(): MatchState[`sType`] {.gensym.} =
      result = MatchState[`sType`](
        retStack: initStack[RetFrame]("return", 8, npegRetStackSize),
        capStack: initStack[CapFrame[`sType`]]("capture", 8),
        backStack: initStack[BackFrame]("backtrace", 8, npegBackStackSize),
        precStack: initStack[PrecFrame]("precedence", 8, 16),
      )
      push(result.precStack, 0)


    proc fn_run(`ms`: var MatchState, `s`: openArray[`sType`], `uId`: var `uType`): MatchResult {.gensym.} =

      # Create local instances of performance-critical MatchState vars, this
      # saves a dereference on each access

      var
        `ip`: range[0..`count`] = `ms`.ip
        `si` = `ms`.si
        `simax` = `ms`.simax

      # These templates are available for code blocks

      template validate(o: bool) {.used.} =
        if not o: return false

      template fail() {.used.} =
        return false

      template push(`s`: string) {.used.} =
        push(`ms`.capStack, CapFrame[`sType`](cft: cftOpen, ck: ckPushed))
        push(`ms`.capStack, CapFrame[`sType`](cft: cftClose, ck: ckPushed, sPushed: `s`))

      # Emit trace and loop code

      try:
        `traceCode`
        `loopCode`
      except CatchableError:
        `exceptionCode`

      # When the parsing machine is done, copy the local copies of the
      # matchstate back, close the capture stack and collect all the captures
      # in the match result

      `ms`.ip = `ip`
      `ms`.si = `si`
      `ms`.simax = `simax`
      result.matchLen = `ms`.si
      result.matchMax = `ms`.simax
      if result.ok and `ms`.capStack.top > 0:
        result.cs = fixCaptures(`s`, `ms`.capStack, FixAll)

    # This is the result of genCode: a Parser object with two function
    # pointers: fn_init: initializes a MatchState object for this parser
    # fn_run: performs the parsing of the subject on the given matchstate

    Parser[`sType`,`uType`](fn_init: fn_init, fn_run: fn_run)

  when npegGcsafe:
    result[0].addPragma(ident("gcsafe"))

  when npegExpand:
    echo result.repr

