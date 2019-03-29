import unittest
import npeg
import json
  
{.push warning[Spacing]: off.}


suite "captures":

  test "string captures":
    doAssert     patt(>1).match("ab").captures == @["a"]
    doAssert     patt(>(>1)).match("ab").captures == @["a", "a"]
    doAssert     patt(>1 * >1).match("ab").captures == @["a", "b"]
    doAssert     patt(>(>1 * >1)).match("ab").captures == @["ab", "a", "b"]
    doAssert     patt(>(>1 * >1)).match("ab").captures == @["ab", "a", "b"]

  test "action captures":
    var a: string
    let p = peg "foo":
      foo <- >1:
        a = c[0]
    doAssert p.match("a").ok
    doassert a == "a"

  test "JSON captures":
    doAssert patt(Js(1)).match("a").capturesJSon == parseJson(""" "a" """)
    doAssert patt(Js(1) * Js(1)).match("ab").capturesJSon == parseJson(""" "b" """)
    doAssert patt(Ja(Js(1) * Js(1))).match("ab").capturesJSon == parseJson(""" ["a", "b"] """)
    doAssert patt(Jo(Jf("one", Js(1))) ).match("ab").capturesJSon == parseJson(""" { "one":"a" } """)
    doAssert patt(Jo(Jf("one", Js(1)) * Jf("two", Js(1))) ).match("ab").capturesJSon == 
      parseJson(""" { "one":"a", "two":"b" } """)


