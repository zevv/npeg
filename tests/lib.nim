import unittest
import strutils
import unicode
import npeg
import npeg/lib/utf8

{.push warning[Spacing]: off.}


suite "unit tests":

  test "utf8 runes":
    doAssert     patt(utf8.any[4] * !1).match("abcd").ok
    doAssert     patt(utf8.any[4] * !1).match("ａｂｃｄ").ok
    doAssert     patt(utf8.any[4] * !1).match("всех").ok
    doAssert     patt(utf8.any[4] * !1).match("乪乫乬乭").ok

  test "utf8 character classes":
    doAssert     patt(utf8.upper).match("Ɵ").ok
    doAssert not patt(utf8.upper).match("ë").ok
    doAssert not patt(utf8.lower).match("Ɵ").ok
    doAssert     patt(utf8.lower).match("ë").ok
