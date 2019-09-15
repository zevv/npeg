
import tables
import macros
import strutils
import npeg/[common,dot,patt]

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


# Manage rules in a grammar

proc hasRule*(g: Grammar, name: string): bool =
  for rule in g.rules:
    if rule.name == name:
      return true

proc getRule*(g: Grammar, name: string): Patt =
  for rule in g.rules:
    if rule.name == name:
      return rule.patt

proc delRule(g: Grammar, name: string) =
  var idx = -1
  for i in 0..g.rules.high:
    if g.rules[i].name == name:
      idx = i
  if idx != -1:
    g.rules.del idx

proc addRule*(grammar: Grammar, name: string, patt1: Patt) =
  if grammar.hasRule(name):
    warning "Redefinition of rule '" & name & "'"
  var patt = patt1
  when npegTrace:
    for i in patt.mitems:
      if i.name == "":
        i.name = name
  grammar.rules.add Rule(name: name, patt: patt)

iterator eachRule*(g: Grammar): (string, Patt) =
  for rule in g.rules:
    yield (rule.name, rule.patt)

proc shadowRule*(grammar: Grammar, name: string): string =
  # Shadow the given name in the grammar by creating an unique new name,
  # and moving the original rule
  var gShadowId {.global.} = 0
  inc gShadowId
  let name2 = name & "-" & $gShadowId
  when npegDebug:
    echo "  shadow ", name, " -> ", name2
  grammar.addRule(name2, grammar.getRule(name))
  grammar.delRule(name)
  return name2


# Manage templates in a grammar

proc hasTemplate*(g: Grammar, name: string): bool =
  for t in g.templates:
    if t.name == name:
      return true

proc getTemplate*(g: Grammar, name: string): Template =
  for t in g.templates:
    if t.name == name:
      return t

proc addTemplate*(g: Grammar, name: string, t: Template) =
  var t2 = t
  t2.name = name
  g.templates.add t2

iterator eachTemplate*(g: Grammar): Template =
  for t in g.templates:
    yield t

# Store a grammar in the library.  The rule names and all unqualified
# identifiers in the grammar are expanded to qualified names in the form
# <libname>.<pattname> to make sure they are easily resolved when they are
# later imported by other grammars.

proc libStore*(libName: string, grammar: Grammar) =

  proc qualify(name: string): string =
    if libName.len > 0: libName & "." & name else: name

  for pattname, patt in grammar.eachRule:
    var pattname2 = qualify(pattname)
    var patt2: Patt
    for i in patt.items:
      var i2 = i
      if i2.op == opCall:
        if "." notin i2.callLabel:
          i2.callLabel = qualify(i2.callLabel)
      patt2.add i2
    gPattLib.addRule(pattname2, patt2)

  for  t in grammar.eachTemplate:
    gPattLib.addTemplate(qualify(t.name), t)


# Try to import the given rule from the pattern library into a grammar. Returns
# true if import succeeded, false if not found.

proc libImportRule*(name: string, grammar: Grammar): bool =
  if gPattLib.hasRule(name):
    grammar.addRule name, gPattLib.getRule(name)
    when npegDebug:
      echo "importing ", name
    return true


proc libImportTemplate*(name: string): Template =
  if gPattLib.hasTemplate(name):
    result = gPattLib.getTemplate(name)



# Link a list of patterns into a grammar, which is itself again a valid
# pattern. Start with the initial rule, add all other non terminals and fixup
# opCall addresses

proc link*(grammar: Grammar, initial_name: string, dot: Dot = nil): Patt =

  if not grammar.hasRule(initial_name):
    error "inital rule '" & initial_name & "' not found"

  var retPatt: Patt
  var symTab = newTwoWayTable[string, int]()

  # Recursively emit a pattern and all patterns it calls which are
  # not yet emitted

  proc emit(name: string) =
    if npegDebug:
      echo "emit ", name
    let patt = grammar.getRule(name)
    symTab.add(name, retPatt.len)
    retPatt.add patt
    retPatt.add Inst(op: opReturn)
    when npegTrace:
      retPatt[retPatt.high].name = retPatt[retPatt.high-1].name

    for i in patt:
      if i.op == opCall and i.callLabel notin symTab:
        if not grammar.hasRule(i.callLabel) and not libImportRule(i.callLabel, grammar):
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

