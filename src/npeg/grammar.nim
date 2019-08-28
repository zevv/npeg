
import tables
import macros
import strutils
import npeg/[common,dot]

#
# Create a new grammar
#

proc newGrammar*(): Grammar =
  new result


# This is the global instance of pattern library. This is itself a grammar
# where all patterns are stored with qualified names in the form of
# <libname>.<pattname>.  At grammar link time all unresolved patterns are
# looked up from this global table.

var gPattLib {.compileTime.} = newGrammar()


# Store a grammar in the library.  The rule names and all unqualified
# identifiers in the grammar are expanded to qualified names in the form
# <libname>.<pattname> to make sure they are easily resolved when they are
# later imported by other grammars.

proc libStore*(libName: string, grammar: Grammar) =

  proc qualify(name: string): string =
    if libName.len > 0: libName & "." & name else: name

  for pattname, patt in grammar.patts:
    var pattname2 = qualify(pattname)
    var patt2: Patt
    for i in patt.items:
      var i2 = i
      if i2.op == opCall:
        if "." notin i2.callLabel:
          i2.callLabel = qualify(i2.callLabel)
      patt2.add i2
    gPattLib.patts[pattname2] = patt2


#
# Add rule to a grammer
#

proc addPatt*(grammar: Grammar, name: string, patt1: Patt) =
  if name in grammar.patts:
    error "Redefinition of rule '" & name & "'"
  var patt = patt1
  when npegTrace:
    for i in patt.mitems:
      if i.name == "":
        i.name = name
      else:
        i.name = " " & i.name
  grammar.patts[name] = patt


# Try to import the given rule from the pattern library into a grammar. Returns
# true if import succeeded, false if not found.

proc libImport*(name: string, grammar: Grammar): bool =
  if name in gPattLib.patts:
    grammar.addPatt name, gPattLib.patts[name]
    when npegDebug:
      echo "importing ", name
    return true


# Shadow the given name in the grammar by creating an unique new name,
# and moving the original rule

proc shadow*(grammar: Grammar, name: string): string =
  var gShadowId {.global.} = 0
  inc gShadowId
  let name2 = name & "-" & $gShadowId
  when npegDebug:
    echo "  shadow ", name, " -> ", name2
  grammar.patts[name2] = grammar.patts[name]
  grammar.patts.del name
  return name2


# Link a list of patterns into a grammar, which is itself again a valid
# pattern. Start with the initial rule, add all other non terminals and fixup
# opCall addresses

proc link*(grammar: Grammar, initial_name: string, dot: Dot = nil): Patt =

  if initial_name notin grammar.patts:
    error "inital rule '" & initial_name & "' not found"

  var retPatt: Patt
  var symTab = newTwoWayTable[string, int]()

  # Recursively emit a pattern and all patterns it calls which are
  # not yet emitted

  proc emit(name: string) =
    if npegDebug:
      echo "emit ", name
    let patt = grammar.patts[name]
    symTab.add(name, retPatt.len)
    retPatt.add patt
    retPatt.add Inst(op: opReturn)

    for i in patt:
      if i.op == opCall and i.callLabel notin symTab:
        if i.callLabel notin grammar.patts and not libImport(i.callLabel, grammar):
          error "Npeg: rule \"" & name & "\" is referencing undefined rule \"" & i.callLabel & "\""
        dot.add(name, i.callLabel, "call")
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



proc `$`*(g: Grammar): string =
  for name, patt in g.patts:
    result.add name & ":\n"
    result.add $patt
