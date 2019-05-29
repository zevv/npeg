
import tables
import macros
import strutils
import npeg/[common,codegen,patt,dot]

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
#  infix       <- ('*' | '|' | '-') * S
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
# Builtins. These correspond to POSIX character classes
#

const builtins = {
  "Alnum":  newPatt({'A'..'Z','a'..'z','0'..'9'}), # Alphanumeric characters
  "Alpha":  newPatt({'A'..'Z','a'..'z'}),          # Alphabetic characters
  "Blank":  newPatt({' ','\t'}),                   # Space and tab
  "Cntrl":  newPatt({'\x00'..'\x1f','\x7f'}),      # Control characters
  "Digit":  newPatt({'0'..'9'}),                   # Digits
  "Graph":  newPatt({'\x21'..'\x7e'}),             # Visible characters
  "Lower":  newPatt({'a'..'z'}),                   # Lowercase characters
  "Print":  newPatt({'\x21'..'\x7e',' '}),         # Visible characters and spaces
  "Space":  newPatt({'\9'..'\13',' '}),            # Whitespace characters
  "Upper":  newPatt({'A'..'Z'}),                   # Uppercase characters
  "Xdigit": newPatt({'A'..'F','a'..'f','0'..'9'}), # Hexadecimal digits
}.toTable()


# Recursively compile a PEG rule to a Pattern

proc parsePatt*(name: string, nn: NimNode, grammar: Grammar = nil, dot: Dot = nil): Patt =

  proc aux(n: NimNode): Patt =

    template krak(n: NimNode, msg: string) =
      error "NPeg: " & msg & ": " & n.repr & "\n"

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
        if n[0].kind != nnkIdent:
          krak n, "syntax error"
        if n.len == 2:
          case n[0].strVal:
            of "Js": return newPatt(aux n[1], ckJString)
            of "Ji": return newPatt(aux n[1], ckJInt)
            of "Jf": return newPatt(aux n[1], ckJFloat)
            of "Ja": return newPatt(aux n[1], ckJArray)
            of "Jo": return newPatt(aux n[1], ckJObject)
            of "Jt": return newPatt(aux n[1], ckJFieldDynamic)
            of "R":
              return newBackrefPatt(n[1].strVal)
            else: krak n, "Unhandled capture type"
        elif n.len == 3:
          if n[0].eqIdent "Jf":
            result = newPatt(aux n[2], ckJFieldFixed)
            result[0].capName = n[1].strVal
          elif n[0].eqIdent "R":
            result = newPatt(aux n[2], ckRef)
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
        let name2 = n.strVal
        if name2 in builtins:
          dot.add(name, name2, "builtin")
          return builtins[name2]
        elif name2 in grammar and grammar[name2].len < INLINE_MAX_LEN:
          dot.add(name, name2, "inline")
          return grammar[name2]
        else:
          dot.add(name, name2, "call")
          return newCallPatt(name2)

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
  dot.addPatt(name, result.len)
  
  when npegTrace:
    for i in result.mitems:
      if i.name == "":
        i.name = name
      else:
        i.name = " " & i.name

