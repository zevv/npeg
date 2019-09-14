#
# Convert a Mouse PEG grammar into NPeg grammar
# http://www.romanredz.se/Mouse/
#

import npeg
import npeg/common
import strutils

# Parse the Mouse grammar into an ASTNode tree

let mouse = peg "mouse":
  mouse     <- A("mouse", *rule) * ?s * !1
  rule      <- ?s * A("rule", >name * s * "=" * s * patt)
  patt      <- A("patt", choice * ?sem * s * ';')
  sem       <- ('{' * @'}')
  choice    <- A("choice", seq * s * *('/' * s * seq))
  seq       <- A("seq", prefixed * *(s * prefixed) * s)
  nonterm   <- A("nonterm", >name)
  prefixed  <- A("pre", ?>'!' * postfixed)
  postfixed <- A("post", (paren | nonterm | lit) * >?postfix)
  lit       <- any | range | set | string
  any       <- A("any", '_')
  range     <- A("range", '[' * >(char * '-' * char) * ']')
  set       <- A("set", '[' * +(char-']') * ']')
  string    <- A("string", '"' * +(char-'"') * '"')
  paren     <- A("paren", '(' * s * choice * s * ')')
  postfix   <- {'+','*','?'}
  name      <- +Alpha
  char      <- A("char", >( ("\\u" * Xdigit[4]) | ('\\' * {'\\','r','n','t','"'}) | 1))
  nl        <- {'\r','\n'}
  s         <- *( +Space | comment | sem )
  comment   <- "//" * >*(1-nl)


# Dump the PEG ast tree into NPeg form

proc dump(a: ASTNode): string =
  proc unescapeChar(s: string): string =
    if s == "'":
      result = "\\'"
    elif s == "\\":
      result = "\\\\"
    elif s.len == 6:
      result = $(parseHexInt(s[2..5]).char.escapeChar)
    else:
      result = s
  case a.id:
    of "mouse":
      for c in a:
        result.add dump(c)
    of "rule":
      return "  " & $a.val & " <- " & dump(a["patt"]) & "\n"
    of "patt":
      return dump a[0]
    of "choice":
      var parts: seq[string]
      for c in a:
        parts.add dump(c)
      return parts.join(" | ")
    of "seq":
      var parts: seq[string]
      for c in a:
        parts.add dump(c)
      return parts.join(" * ")
    of "paren":
      return "( " & dump(a[0]) & " )"
    of "pre":
      return a.val & dump(a[0])
    of "post":
      return a.val & dump(a[0])
    of "nonterm":
      return a.val
    of "any":
      return "1"
    of "string":
      result.add '"'
      for c in a:
        result.add unescapeChar(c.val)
      result.add '"'
    of "set":
      var cs: seq[string]
      for c in a: cs.add unescapeChar(c.val)
      return "{'" & cs.join("','") & "'}"
    of "range":
      return "{'" & escapeChar(a.val[0]) & "'..'" & escapeChar(a.val[2]) & "'}"
    else:
      echo "\nUnhnandled " & a.id
      quit 1


# http://www.romanredz.se/Mouse/Java.1.6.peg

let r = mouse.matchFile("/tmp/Java.1.6.peg")
if not r.ok:
  echo "Error parsing at ", r.matchMax
  quit 1

echo "import npeg"
echo "let r = peg CompilationUnit:"

echo dump(r.capturesAst())

