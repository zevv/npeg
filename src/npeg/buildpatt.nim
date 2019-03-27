
import tables
import macros
import strutils

import common
import codegen
import patt

#
# The complete PEG syntax parsed by parsePatt(). In PEG. How meta.
#
#  name        <- +(alphanum | '_' | '-')
#  S           <- *{' ','\t'}
#  nl          <- +{'\r','\n'}
#  alpha       <- {'A'..'Z','a'..'z'}
#  digit       <- {'0'..'9'}
#  hex         <- digit | {'A'..'F','a'..'f'}
#  alphanum    <- alpha | digit
#  number      <- +digit
#  string      <- '"' * +(1-'"') * '"' * S
#  set         <- '{' * S * setbody * *( ',' * S * setbody) * '}' * S
#  setbody     <- (setrange | char) * S
#  setrange    <- char * ".." * char * S
#  char        <- "'" * charbody * "'" * S
#  charbody    <- ("\\" * {'t','r','n','\\'}) | ("\\x" * hex{2}) | 1
#  atom        <- (number | string | set | char | name)
#  infix       <- ('*' | '|' | '-' | '%') * S
#  postfix     <- '{' * number * ?( ".." * number) * "}"
#  prefix      <- '!' | '*' | '+' | '?' | capture
#  capture     <- '>' | "Js" | "Jo" | "Ja" | "Jf" | "Ji"
#  fieldcap    <- "Jf(" * S * string * S * "," * S * patt * ")"
#  rule        <- S * name * S * "<-" * S * patt * nl
#  patt        <- exp * *(infix * exp)
#  exp         <- (fieldcap | ?prefix * term * ?postfix) * S
#  term        <- atom | ('(' * S * patt * S * ')') * S
#  grammar     <- *rule * !1
#

type Grammar* = TableRef[string, Patt]


#
# Builtins
#
  
const builtins = {
  "Upper": newPatt {'A'..'Z'},
  "Lower": newPatt {'a'..'z'},
  "Alpha": newPatt {'A'..'Z','a'..'z'},
  "Digit": newPatt {'0'..'9'},
  "Space": newPatt {'\9'..'\13',' '},
  "Word": newPatt {'A'..'Z','a'..'z','0'..'9'},
  "HexDigit": newPatt {'A'..'F','a'..'f','0'..'9'},
}.toTable()


# Recursively compile a PEG rule to a Pattern

proc parsePatt*(name: string, nn: NimNode, grammar: Grammar = nil): Patt =

  proc aux(n: NimNode): Patt =

    template krak(n: NimNode, msg: string) =
      error "NPeg: " & msg & ": " & n.repr & "\n" & n.astGenRepr, n

    case n.kind:

      of nnKPar, nnkStmtList:
        if n.len == 1: return aux n[0]
        elif n.len == 2:
          result = newPatt(aux n[0], ckAction)
          result[result.high].capAction = n[1]
        else: krak n, "Too many expressions in parenthesis"

      of nnkIntLit:
        return newPatt(n.intVal)

      of nnkStrLit:
        return newPatt(n.strval, opStr)

      of nnkCharLit:
        return newPatt($n.intVal.char, opStr)

      of nnkCall:
        if n.len == 2:
          let p = aux n[1]
          case n[0].strVal:
            of "Js": return newPatt(p, ckJString)
            of "Ji": return newPatt(p, ckJInt)
            of "Jf": return newPatt(p, ckJFloat)
            of "Ja": return newPatt(p, ckJArray)
            of "Jo": return newPatt(p, ckJObject)
            of "Jt": return newPatt(p, ckJFieldDynamic)
            else: krak n, "Unhandled capture type"
        elif n.len == 3:
          if n[0].eqIdent "Jf":
            result = newPatt(aux n[2], ckJFieldFixed)
            result[0].capName = n[1].strVal
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
        return p

      of nnkInfix:
        if n[0].eqIdent("%"):
          result = newPatt(aux n[1], ckAction)
          result[result.high].capAction = n[2]
        else:
          let (p1, p2) = (aux n[1], aux n[2])
          case n[0].strVal:
            of "*": return p1 * p2
            of "-": return p1 - p2
            of "|": return p1 | p2
            else: krak n, "Unhandled infix operator"

      of nnkBracketExpr:
        let p = aux(n[0])
        if n[1].kind == nnkIntLit:
          return p{n[1].intVal}
        elif n[1].kind == nnkInfix and n[1][0].eqIdent(".."):
          return p{n[1][1].intVal..n[1][2].intVal}
        else: krak n, "syntax error"

      of nnkIdent:
        let name = n.strVal
        if name in builtins:
          return builtins[name]
        elif name in grammar:
          return grammar[name]
        else:
          return newCallPatt(name)

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
          return newPatt(1)
        else:
          return newPatt(cs)

      of nnkCallStrLit:
        case n[0].strVal:
          of "i": return newPatt(n[1].strval, opIStr)
          of "E": return newErrorPatt(n[1].strval)
          else: krak n, "unhandled string prefix"
      else:
        krak n, "syntax error"

  result = aux(nn)
  
  when npegTrace:
    for i in result.mitems:
      if i.name == "":
        i.name = name
      else:
        i.name = " " & i.name


