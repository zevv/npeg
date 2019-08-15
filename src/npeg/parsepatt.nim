
import tables
import macros
import npeg/[common,patt,dot,lib]


# Shadow the given name in the grammar by creating an unique new name,
# and moving the original rule

var gShadowId = 0
proc shadow(grammar: Grammar, name: string): string =
  inc gShadowId
  let name2 = name & "-" & $gShadowId
  when npegDebug:
    echo "  shadow ", name, " -> ", name2
  grammar[name2] = grammar[name]
  grammar.del name
  return name2


# Recursively compile a PEG rule to a Pattern

proc parsePatt*(name: string, nn: NimNode, grammar: Grammar, dot: Dot = nil): Patt =

  when npegDebug:
    echo "parse ", name, " <- ", nn.repr

  proc aux(n: NimNode): Patt =

    template krak(n: NimNode, msg: string) =
      error "NPeg: " & msg & ": " & n.repr & "\n"

    template inlineOrCall(name2: string) =

      # Try to import symbol early so we might be able to inline or shadow it
      if name2 notin grammar:
        discard libImport(name2, grammar)

      if name == name2:
        if name in grammar:
          let nameShadowed = grammar.shadow(name)
          result = newCallPatt(nameShadowed)
        else:
          error "Trying to shadow undefined rule '" & name & "'"

      elif name2 in grammar and grammar[name2].len < npegInlineMaxLen:
        when npegDebug:
          echo "  inline ", name2
        dot.add(name, name2, "inline")
        result = grammar[name2]

      else:
        when npegDebug:
          echo "  call ", name2
        dot.add(name, name2, "call")
        result = newCallPatt(name2)

    case n.kind:

      of nnKPar, nnkStmtList:
        if n.len == 1: result = aux n[0]
        elif n.len == 2:
          result = newPatt(aux n[0], ckAction)
          result[result.high].capAction = n[1]
        else: krak n, "Too many expressions in parenthesis"

      of nnkIntLit:
        result = newPatt(n.intVal)

      of nnkStrLit:
        result = newPatt(n.strval, opStr)

      of nnkCharLit:
        result = newPatt($n.intVal.char, opStr)

      of nnkCall:
        if n[0].kind != nnkIdent:
          krak n, "syntax error"
        if n.len == 2:
          case n[0].strVal:
            of "Js": result = newPatt(aux n[1], ckJString)
            of "Ji": result = newPatt(aux n[1], ckJInt)
            of "Jb": result = newPatt(aux n[1], ckJBool)
            of "Jf": result = newPatt(aux n[1], ckJFloat)
            of "Ja": result = newPatt(aux n[1], ckJArray)
            of "Jo": result = newPatt(aux n[1], ckJObject)
            of "Jt": result = newPatt(aux n[1], ckJFieldDynamic)
            of "R":
              result = newBackrefPatt(n[1].strVal)
            else: krak n, "Unhandled capture type"
        elif n.len == 3:
          if n[0].eqIdent "Jf": result = newPatt(aux n[2], ckJFieldFixed, n[1].strVal)
          elif n[0].eqIdent "A": result = newPatt(aux n[2], ckAST, n[1].strVal)
          elif n[0].eqIdent "R": result = newPatt(aux n[2], ckRef, n[1].strVal)
          else: krak n, "Unhandled capture type"

      of nnkPrefix:
        # Nim combines all prefix chars into one string. Handle prefixes
        # chars right to left
        let cs = n[0].strVal
        var p = aux n[1]
        for i in 1..cs.len:
          let c = cs[cs.len-i]
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
        inlineOrCall(n.strVal)

      of nnkDotExpr:
        inlineOrCall(n[0].strVal & "." & n[1].strVal)

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
        krak n, "syntax error"

    when npegTrace:
      for i in result.mitems:
        if i.pegRepr == "":
          i.pegRepr = n.repr

  result = aux(nn)
  dot.addPatt(name, result.len)

