
import tables, macros, sequtils, strutils, algorithm
import npeg/[common,patt,dot,grammar]

when npegGraph:
  import npeg/[railroad]


# Recursively compile a PEG rule to a Pattern

proc parsePatt*(pattName: string, nn: NimNode, grammar: Grammar, dot: Dot = nil): Patt =

  when npegDebug:
    echo "parse ", pattName, " <- ", nn.repr

  proc aux(n: NimNode): Patt =

    setKrakNode(n)

    proc inlineOrCall(callName: string): Patt =

      # Try to import symbol early so we might be able to inline or shadow it
      if callName notin grammar.rules:
        discard libImportRule(callName, grammar)

      if pattName == callName:
        if pattName in grammar.rules:
          let nameShadowed = grammar.shadow(pattName)
          return newCallPatt(nameShadowed)

      if callName in grammar.rules and grammar.rules[callName].patt.len < npegInlineMaxLen:
        when npegDebug:
          echo "  inline ", callName
        dot.add(pattName, callName, "inline")
        return grammar.rules[callName].patt

      else:
        when npegDebug:
          echo "  call ", callName
        dot.add(pattName, callName, "call")
        return newCallPatt(callName)

    proc applyTemplate(tName: string, arg: NimNode): NimNode =
      let t = if tName in grammar.templates:
        grammar.templates[tName]
      else:
        libImportTemplate(tName)
      if t != nil:
        if arg.len-1 != t.args.len:
          krak arg, "Wrong number of arguments for template " & tName & "(" & $(t.args.join(",")) & ")"
        proc aux(n: NimNode): NimNode =
          if n.kind == nnkIdent and n.strVal in t.args:
            result = arg[ find(t.args, n.strVal)+1 ]
          else:
            result = copyNimNode(n)
            for nc in n:
              result.add aux(nc)
        result = aux(t.code).flattenChoice()
        when npegDebug:
          echo "template ", tName, " = \n  in:  ", n.repr, "\n  out: ", result.repr

    case n.kind:

      of nnkPar:
        if n.len > 1:
          krak n, "syntax error. Did you mean '|'?"
        result = aux n[0]

      of nnkIntLit:
        result = newPatt(n.intVal)

      of nnkStrLit:
        result = newPatt(n.strVal)

      of nnkCharLit:
        result = newPatt($n.intVal.char)

      of nnkCall:
        var name: string
        if n[0].kind == nnkIdent:
          name = n[0].strVal
        elif n[0].kind == nnkDotExpr:
          name = n[0].repr
        else:
          krak n, "syntax error"
        let n2 = applyTemplate(name, n)
        if n2 != nil:
          result = aux n2
        elif name == "choice":
          result = choice(n[1..^1].map(aux))
        elif n.len == 2:
          case name
            of "R": result = newBackrefPatt(n[1].strVal)
        elif n.len == 3:
          case name
            of "R": result = newPatt(aux n[2], ckRef, n[1].strVal)
        if result.len == 0:
          krak n, "Unknown template or capture '" & name & "'"

      of nnkPrefix:
        # Nim combines all prefix chars into one string. Handle prefixes
        # chars right to left
        var p = aux n[1]
        for c in n[0].strVal.reversed:
          case c:
            of '?': p = ?p
            of '+': p = +p
            of '*': p = *p
            of '!': p = !p
            of '&': p = &p
            of '>': p = >p
            of '@': p = @p
            else: krak n, "Unhandled prefix operator"
        result = p

      of nnkInfix:
        case n[0].strVal:
          of "*", "∙": result = aux(n[1]) * aux(n[2])
          of "-": result = aux(n[1]) - aux(n[2])
          of "^": result = newPattAssoc(aux(n[1]), intVal(n[2]), assocLeft)
          of "^^": result = newPattAssoc(aux(n[1]), intVal(n[2]), assocRight)
          else: krak n, "Unhandled infix operator"

      of nnkBracketExpr:
        let p = aux(n[0])
        if n[1].kind == nnkIntLit:
          result = p{n[1].intVal}
        elif n[1].kind == nnkInfix and n[1][0].eqIdent(".."):
          result = p{n[1][1].intVal..n[1][2].intVal}
        else: krak n, "syntax error"

      of nnkIdent:
        result = inlineOrCall(n.strVal)

      of nnkDotExpr:
        result = inlineOrCall(n.repr)

      of nnkCurly:
        var cs: CharSet
        for nc in n:
          if nc.kind == nnkCharLit:
            cs.incl nc.intVal.char
          elif nc.kind == nnkInfix:
            if nc[0].kind == nnkIdent and nc[0].eqIdent(".."):
              for c in nc[1].intVal..nc[2].intVal:
                cs.incl c.char
            else:
              krak n, "syntax error"
          else:
            krak n, "syntax error"
        if cs.card == 0:
          result = newPatt(1)
        else:
          result = newPatt(cs)

      of nnkCallStrLit:
        case n[0].strVal:
          of "i": 
            for c in n[1].strVal:
              result.add newPatt({c.toLowerAscii, c.toUpperAscii})
          of "E": result = newErrorPatt(n[1].strVal)
          else: krak n, "unhandled string prefix"

      of nnkBracket:
        result.add newLitPatt n[0]

      else:
        echo n.astGenRepr
        krak n, "syntax error"

    for i in result.mitems:
      if i.nimNode == nil:
        i.nimNode = n

  result = aux(nn.flattenChoice())
  dot.addPatt(pattName, result.len)


#
# Parse a grammar. A grammar consists of named rules, where each rule is one
# pattern
#

proc parseGrammar*(ns: NimNode, dot: Dot=nil, dumpRailroad = true): Grammar =
  result = new Grammar

  for n in ns:

    if n.kind == nnkInfix and n[0].eqIdent("<-"):

      case n[1].kind
      of nnkIdent, nnkDotExpr, nnkPrefix:
        let name = if n[1].kind == nnkPrefix:
                     when declared(expectIdent):
                       expectIdent n[1][0], ">"
                     n[1][1].repr
                   else: n[1].repr
        var patt = parsePatt(name, n[2], result, dot)
        if n.len == 4:
          patt = newPatt(patt, ckAction)
          patt[patt.high].capAction = n[3]
        result.addRule(name, if n[1].kind == nnkPrefix: >patt else: patt, n.repr, n.lineInfoObj)

        when npegGraph:
          if dumpRailroad:
            echo parseRailroad(n[2], result).wrap(name)

      of nnkCall:
        if n.len > 3:
          error "Code blocks can not be used on templates", n[3]
        var t = Template(name: n[1][0].strVal, code: n[2])
        for i in 1..<n[1].len:
          t.args.add n[1][i].strVal
        result.templates[t.name] = t

      else:
        error "Expected PEG rule name but got " & $n[1].kind, n

    else:
      error "Expected PEG rule (name <- ...)", n

