
import tables
import macros

import common
import patt
import buildpatt


proc add*(grammar: var Grammar, name: string, n: NimNode) =

  if name in grammar:
    error "Redefinition of rule '" & name & "'", n

  var patt = buildPatt(n, grammar)

  when npegTrace:
    for i in patt.mitems:
      if i.name == "":
        i.name = name
      else:
        i.name = " " & i.name

  grammar[name] = patt


# Link a list of patterns into a grammar, which is itself again a valid
# pattern. Start with the initial rule, add all other non terminals and fixup
# opCall addresses

proc link*(grammar: Grammar, initial_name: string): Patt =

  if initial_name notin grammar:
    error "inital rule '" & initial_name & "' not found"

  var retPatt: Patt
  var symTab = newTwoWayTable[string, int]()

  # Recursively emit a pattern and all patterns it calls which are
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

  for ip, i in retPatt.mpairs:
    if i.op == opCall:
      i.callOffset = symtab.get(i.callLabel) - ip
    if i.op == opCall and retPatt[ip+1].op == opReturn:
      i.op = opJump

  result = retPatt
  when npegTrace:
    result.dump(symTab)


proc newGrammar*(): Grammar =
  result = newTable[string, Patt]()


proc newGrammar*(ns: NimNode): Grammar =
  var grammar = newGrammar()
  for n in ns:
    if n.kind == nnkInfix and n[0].kind == nnkIdent and
       n[1].kind == nnkIdent and n[0].eqIdent("<-"):
      grammar.add(n[1].strVal, n[2])
    else:
      echo n.astGenRepr
      error "Expected PEG rule (name <- ...)", n
  grammar

