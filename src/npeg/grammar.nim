
import tables
import macros
import strutils
import npeg/[common,dot]

# This is the global instance of pattern library. This is itself a grammar
# where all patterns are stored with qualified names in the form of
# <libname>.<pattname>.  At grammar link time all unresolved patterns are
# looked up from this global table.

var gPattLib {.compileTime.} = new Grammar



# Store a grammar in the library.  The rule names and all unqualified
# identifiers in the grammar are expanded to qualified names in the form
# <libname>.<pattname> to make sure they are easily resolved when they are
# later imported by other grammars.

proc libStore*(libName: string, grammar: Grammar) =

  proc qualify(name: string): string =
    if libName.len > 0: libName & "." & name else: name

  for rulename, rule in grammar.rules:
    var rulename2 = qualify(rulename)
    var rule2 = Rule(name: rulename2)
    for i in rule.patt.items:
      var i2 = i
      if i2.op == opCall:
        if "." notin i2.callLabel:
          i2.callLabel = qualify(i2.callLabel)
      rule2.patt.add i2
    gPattLib.rules[rulename2] = rule2

  for tname, t in grammar.templates:
    gPattLib.templates[qualify(tname)] = t

#
# Add rule to a grammer
#

proc addRule*(grammar: Grammar, name: string, patt: Patt, repr: string = "", lineInfo: LineInfo = LineInfo()) =
  if name in grammar.rules:
    warning "Redefinition of rule '" & name & "'"
  var rule = Rule(name: name, patt: patt, repr: repr, lineInfo: lineInfo)
  for i in rule.patt.mitems:
    if i.name == "":
      i.name = name
  grammar.rules[name] = rule

# Try to import the given rule from the pattern library into a grammar. Returns
# true if import succeeded, false if not found.

proc libImportRule*(name: string, grammar: Grammar): bool =
  if name in gPattLib.rules:
    grammar.addRule name, gPattLib.rules[name].patt
    when npegDebug:
      echo "importing ", name
    return true


proc libImportTemplate*(name: string): Template =
  if name in gPattLib.templates:
    result = gPattLib.templates[name]


# Shadow the given name in the grammar by creating an unique new name,
# and moving the original rule

proc shadow*(grammar: Grammar, name: string): string =
  var gShadowId {.global.} = 0
  inc gShadowId
  let name2 = name & "-" & $gShadowId
  when npegDebug:
    echo "  shadow ", name, " -> ", name2
  grammar.rules[name2] = grammar.rules[name]
  grammar.rules.del name
  return name2


# Link a list of patterns into a grammar, which is itself again a valid
# pattern. Start with the initial rule, add all other non terminals and fixup
# opCall addresses

proc link*(grammar: Grammar, initial_name: string, dot: Dot = nil): Program =

  if initial_name notin grammar.rules:
    error "inital rule '" & initial_name & "' not found"

  var retPatt: Patt
  var symTab: SymTab
  var ruleRepr: Table[int, string]

  # Recursively emit a pattern and all patterns it calls which are
  # not yet emitted

  proc emit(name: string) =
    if npegDebug:
      echo "emit ", name
    let rule = grammar.rules[name]
    if rule.patt.len > 0:
      let ip = retPatt.len
      symTab.add(ip, name, rule.repr, rule.lineInfo)
      retPatt.add rule.patt
      retPatt.add Inst(op: opReturn, name: rule.patt[0].name)

    for i in rule.patt:
      if i.op == opCall and i.callLabel notin symTab:
        if i.callLabel notin grammar.rules and not libImportRule(i.callLabel, grammar):
          error "Npeg: rule \"" & name & "\" is referencing undefined rule \"" & i.callLabel & "\""
        dot.add(name, i.callLabel, "call")
        emit i.callLabel

  emit initial_name

  # Fixup call addresses and do tail call optimization

  for ip, i in retPatt.mpairs:
    if i.op == opCall:
      i.callOffset = symTab[i.callLabel].ip - ip
    if i.op == opCall and retPatt[ip+1].op == opReturn:
      i.op = opJump

  # Choice/Commit pairs that touch because of head fail optimization can be
  # replaced by a jump and a nop

  when npegOptChoiceCommit:
    for i in 0..<retPatt.high:
      if retPatt[i+0].op == opChoice and retPatt[i+1].op == opCommit:
        retPatt[i+0] = Inst(op: opJump, callOffset: retPatt[i+1].ipOffset + 1)
        retPatt[i+1] = Inst(op: opNop)

  # Trailing opFail is used by the codegen

  symTab.add(retPatt.len, "_fail")
  retPatt.add Inst(op: opFail)

  # Calc indent level for instructions

  var indent = 0
  for ip, i in retPatt.mpairs:
    if i.op in {opCapClose, opCommit}: dec indent
    i.indent = indent
    if i.op in {opCapOpen, opChoice}: inc indent

  result = Program(patt: retPatt, symTab: symTab)

  when npegTrace:
    echo result

