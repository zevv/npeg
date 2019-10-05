
import tables
import macros
import strutils
import npeg/[common,patt,dot,grammar]

when npegGraph:
  import npeg/[railroad]


# Recursively compile a PEG rule to a Pattern

proc parsePatt*(name: string, nn: NimNode, grammar: Grammar, dot: Dot = nil): Patt =

  when npegDebug:
    echo "parse ", name, " <- ", nn.repr

  proc aux(n: NimNode): Patt =

    template krak(n: NimNode, msg: string) =
      error "NPeg: error at '" & n.repr & "': " & msg & "\n", n

    proc inlineOrCall(name2: string): Patt =

      # Try to import symbol early so we might be able to inline or shadow it
      if name2 notin grammar.patts:
        discard libImportRule(name2, grammar)

      if name == name2:
        if name in grammar.patts:
          let nameShadowed = grammar.shadow(name)
          return newCallPatt(nameShadowed)

      if name2 in grammar.patts and grammar.patts[name2].len < npegInlineMaxLen:
        when npegDebug:
          echo "  inline ", name2
        dot.add(name, name2, "inline")
        return grammar.patts[name2]

      else:
        when npegDebug:
          echo "  call ", name2
        dot.add(name, name2, "call")
        return newCallPatt(name2)

    proc applyTemplate(name: string, arg: NimNode): NimNode =
      let t = if name in grammar.templates:
        grammar.templates[name]
      else:
        libImportTemplate(name)
      if t != nil:
        if arg.len-1 != t.args.len:
          krak arg, "Wrong number of arguments for template " & name & "(" & $(t.args.join(",")) & ")"
        when npegDebug:
          echo "template ", name, " = \n  in:  ", n.repr, "\n  out: ", result.repr
        proc aux(n: NimNode): NimNode =
          if n.kind == nnkIdent and n.strVal in t.args:
            result = arg[ find(t.args, n.strVal)+1 ]
          else:
            result = copyNimNode(n)
            for nc in n:
              result.add aux(nc)
        result = aux(t.code)

    case n.kind:

      of nnKPar:
        result = aux n[0]

      of nnkIntLit:
        result = newPatt(n.intVal)

      of nnkStrLit:
        result = newPatt(n.strval, opStr)

      of nnkCharLit:
        result = newPatt($n.intVal.char, opChr)

      of nnkCall:
        var name: string
        if n[0].kind == nnkIdent:
          name = n[0].strVal
        elif n[0].kind == nnkDotExpr:
          name = n[0][0].strVal & "." & n[0][1].strVal
        else:
          krak n, "syntax error"
        let n2 = applyTemplate(name, n)
        if n2 != nil:
          result = aux n2
        elif n.len == 2:
          case name
            of "Js": result = newPatt(aux n[1], ckJString)
            of "Ji": result = newPatt(aux n[1], ckJInt)
            of "Jb": result = newPatt(aux n[1], ckJBool)
            of "Jf": result = newPatt(aux n[1], ckJFloat)
            of "Ja": result = newPatt(aux n[1], ckJArray)
            of "Jo": result = newPatt(aux n[1], ckJObject)
            of "Jt": result = newPatt(aux n[1], ckJFieldDynamic)
            of "R": result = newBackrefPatt(n[1].strVal)
        elif n.len == 3:
          case name
            of "Jf": result = newPatt(aux n[2], ckJFieldFixed, n[1].strVal)
            of "A": result = newPatt(aux n[2], ckAST, n[1].strVal)
            of "R": result = newPatt(aux n[2], ckRef, n[1].strVal)
        if result.len == 0:
          krak n, "Unknown template or capture '" & name & "'"

      of nnkPrefix:
        # Nim combines all prefix chars into one string. Handle prefixes
        # chars right to left
        let cs = n[0].strVal
        var p = aux n[1]
        for i in 1..cs.len:
          case cs[cs.len-i]:
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
        let (p1, p2) = (aux n[1], aux n[2])
        case n[0].strVal:
          of "*": result = p1 * p2
          of "-": result = p1 - p2
          of "|": result = p1 | p2
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
        result = inlineOrCall(n[0].strVal & "." & n[1].strVal)

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
          of "i": result = newPatt(n[1].strval, opIStr)
          of "E": result = newErrorPatt(n[1].strval)
          else: krak n, "unhandled string prefix"

      else:
        echo n.astGenRepr
        krak n, "syntax error"

    for i in result.mitems:
      if i.pegRepr == "":
        i.pegRepr = n.repr

  result = aux(nn)
  dot.addPatt(name, result.len)


#
# Parse a grammar. A grammar consists of named rules, where each rule is one
# pattern
#

proc parseGrammar*(ns: NimNode, dot: Dot=nil, dumpRailroad = true): Grammar =
  result = newGrammar()

  for n in ns:

    if n.kind == nnkInfix and n[0].eqIdent("<-"):

      if n[1].kind in { nnkIdent, nnkDotExpr}:
        var name: string
        if n[1].kind == nnkIdent:
          name = n[1].strVal
        else:
          name = n[1][0].strVal & "." & n[1][1].strVal
        var patt = parsePatt(name, n[2], result, dot)
        if n.len == 4:
          patt = newPatt(patt, ckAction)
          patt[patt.high].capAction = n[3]
        result.addPatt(name, patt)

        when npegGraph:
          if dumpRailroad:
            echo parseRailroad(n[2], result).wrap(name)

      elif n[1].kind == nnkCall:
        var t = Template(name: n[1][0].strVal, code: n[2])
        for i in 1..<n[1].len:
          t.args.add n[1][i].strVal
        result.templates[t.name] = t

      else:
        error "Expected PEG rule name but got " & $n[1].kind, n

    else:
      error "Expected PEG rule (name <- ...)", n

