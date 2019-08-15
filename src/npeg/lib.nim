
import tables
import common
import strutils


# This is the global instance of pattern library. This is itself a grammar
# where all patterns are stored with qualified names in the form of
# <libname>.<pattname>.  At grammar link time all unresolved patterns are
# looked up from this global table.

var gPattLib {.compileTime.} = newTable[string, Patt]()


# Store a grammar in the library.  The rule names and all unqualified
# identifiers in the grammar are expanded to qualified names in the form
# <libname>.<pattname> to make sure they are easily resolved when they are
# later imported by other grammars.

proc libStore*(libName: string, grammar: Grammar) =

  proc qualify(name: string): string =
    if libName.len > 0: libName & "." & name else: name

  for pattname, patt in grammar.pairs:
    var pattname2 = qualify(pattname)
    var patt2: Patt
    for i in patt.items:
      var i2 = i
      if i2.op == opCall:
        if "." notin i2.callLabel:
          i2.callLabel = qualify(i2.callLabel)
      patt2.add i2
    gPattLib[pattname2] = patt2


# Try to import the given rule from the pattern library into a grammar. Returns
# true if import succeeded, false if not found.

proc libImport*(name: string, grammar: Grammar): bool =
  if name in gPattLib:
    grammar.add name, gPattLib[name]
    when npegDebug:
      echo "importing ", name
    return true

