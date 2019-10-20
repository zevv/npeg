
import tables
import macros
import strutils
import npeg/[common,dot]

#
# Create a new grammar
#

proc newGrammar*(): Grammar =
  Grammar(
    rules: newTable[string, Rule](),
    templates: newTable[string, Template]()
  )


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

  for rulename, rule in grammar.rules:
    gPattLib.rules[qualify(rulename)] = rule

  for tname, t in grammar.templates:
    gPattLib.templates[qualify(tname)] = t

#
# Add rule to a grammer
#

proc addRule*(grammar: Grammar, name: string, rule1: Rule) =
  if name in grammar.rules:
    warning "Redefinition of rule '" & name & "'"
  var rule = rule1
  for i in rule.patt.mitems:
    if i.name == "":
      i.name = name
  grammar.rules[name] = rule


# Try to import the given rule from the pattern library into a grammar. Returns
# true if import succeeded, false if not found.

proc libImportRule*(name: string, grammar: Grammar): bool =
  if name in gPattLib.rules:
    grammar.addRule name, gPattLib.rules[name]
    when npegDebug:
      echo "importing ", name
    return true

proc libImportRule*(name: string): Rule =
  if name in gPattLib.rules:
    when npegDebug:
      echo "importing ", name
    result = gPattLib.rules[name]

proc libImportTemplate*(name: string): Template =
  if name in gPattLib.templates:
    result = gPattLib.templates[name]


# Shadow the given name in the grammar by creating an unique new name,
# and moving the original rule

proc shadow*(rule: Rule): Rule =
  var gShadowId {.global.} = 0
  inc gShadowId
  let name2 = rule.name & "-" & $gShadowId
  when npegDebug:
    echo "  shadow ", rule.name, " -> ", name2

  Rule(name: name2, libName: rule.libname, code: rule.code,
                   action: rule.action, patt: rule.patt, state: rule.state)


