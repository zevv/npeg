
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

    var patt = buildPatt(n[2], result)
    when npegTrace:
      for i in patt.mitems:
        if i.name == "":
          i.name = pname
        else:
          i.name = " " & i.name
    result[pname] = patt


# Link a list of patterns into a grammar, which is itself again a valid
# pattern. Start with the initial rule, add all other non terminals and fixup
# opCall addresses

proc linkGrammar(grammar: Grammar, initial_name: string): Patt =

  if initial_name notin grammar:
    error "inital pattern '" & initial_name & "' not found"

  var retPatt: Patt
  var symTab = newTwoWayTable[string, int]()

  # Recursively emit a pattern, and all patterns it calls which are
  # not yet emitted

  proc emit(name: string) =
    let patt = grammar[name]
    symTab.add(name, retPatt.len)
    retPatt.add patt
    retPatt.add Inst(op: opReturn)

    for i in patt:
      if i.op == opCall and i.callLabel notin symTab:
        if i.callLabel notin grammar:
          error "Npeg: rule \"" & name & "\" is referencing undefined rule \"" & i.callLabel & "\""
        emit i.callLabel

  emit initial_name

  # Fixup call addresses and do tail call optimization

  for n, i in retPatt.mpairs:
    if i.op == opCall:
      i.callAddr = symtab.get(i.callLabel)
    if i.op == opCall and retPatt[n+1].op == opReturn:
      i.op = opJump

  result = retPatt
  when npegTrace:
    result.dump(symTab)


proc buildGrammar*(name: string, ns: NimNode): Patt =
  let grammar = parseGrammar(ns)
  linkGrammar(grammar, name)

