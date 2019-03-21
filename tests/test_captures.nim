import unittest
import npeg
import json
  
{.push warning[Spacing]: off.}
abortOnError = true


suite "npeg":

  test "string captures":
    doAssert     patt(>1)("ab").captures == @["a"]
    doAssert     patt(>(>1))("ab").captures == @["a", "a"]
    doAssert     patt(>1 * >1)("ab").captures == @["a", "b"]
    doAssert     patt(>(>1 * >1))("ab").captures == @["ab", "a", "b"]
    doAssert     patt(>(>1 * >1))("ab").captures == @["ab", "a", "b"]

  test "action captures":
    var a: string
    doAssert patt(>1 % (a=c[0]))("a").ok
    doassert a == "a"

  test "JSON captures":
    doAssert patt(Js(1))("a").capturesJSon == parseJson(""" "a" """)
    doAssert patt(Js(1) * Js(1))("ab").capturesJSon == parseJson(""" "b" """)
    doAssert patt(Ja(Js(1) * Js(1)))("ab").capturesJSon == parseJson(""" ["a", "b"] """)
    doAssert patt(Jo(Jf("one", Js(1))) )("ab").capturesJSon == parseJson(""" { "one":"a" } """)
    doAssert patt(Jo(Jf("one", Js(1)) * Jf("two", Js(1))) )("ab").capturesJSon == 
      parseJson(""" { "one":"a", "two":"b" } """)


