
import tables
import macros

import common
import patt
import buildpatt

# Compile the PEG to a table of patterns

proc parseGrammar(ns: NimNode): Grammar =
  result = newTable[string, Patt]()
  for n in ns:
    n.expectKind nnkInfix
    n[0].expectKind nnkIdent
    n[1].expectKind nnkIdent
    if not n[0].eqIdent("<-"):
      error "Expected <-", n
    let pname = n[1].strVal
    if pname in result:
      error "Redefinition of rule '" & pname & "'", n
    result[pname] = buildPatt(n[2], result)


# Link a list of patterns into a grammar, which is itself again a valid
# pattern. Start with the initial rule, add all other non terminals and fixup
# opCall addresses

proc linkGrammar(patts: Grammar, initial_name: string): Patt =

  if initial_name notin patts:
    error "inital pattern '" & initial_name & "' not found"

  var grammar: Patt
  var symTab = newTable[string, int]()

  # Recursively emit a pattern, and all patterns it calls which are
  # not yet emitted

  proc emit(name: string) =
    when npegTrace:
      echo "Emit ", name
    let patt = patts[name]
    symTab[name] = grammar.len
    grammar.add patt
    grammar.add Inst(op: opReturn)

    for i in patt:
      if i.op == opCall and i.callLabel notin symTab:
        if i.callLabel notin patts:
          error "Npeg: rule \"" & name & "\" is referencing undefined rule \"" & i.callLabel & "\""
        emit i.callLabel

  emit initial_name

  # Fixup call addresses and do tail call optimization

  for n, i in grammar.mpairs:
    if i.op == opCall:
      i.callAddr = symtab[i.callLabel]
    if i.op == opCall and grammar[n+1].op == opReturn:
      i.op = opJump

  return grammar


proc buildGrammar*(name: string, ns: NimNode): Patt =
  let grammar = parseGrammar(ns)
  linkGrammar(grammar, name)

