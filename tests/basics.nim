import unittest
import npeg
  
{.push warning[Spacing]: off.}


suite "unit tests":

  test "atoms":
    doAssert     patt(0 * "a").match("a").ok
    doAssert     patt(1).match("a").ok
    doAssert     patt(1).match("a").ok
    doAssert     patt(2).match("a").ok == false
    doAssert     patt("a").match("a").ok
    doAssert     patt("a").match("b").ok == false
    doAssert     patt("abc").match("abc").ok
    doAssert     patt({'a'}).match("a").ok
    doAssert     patt({'a'}).match("b").ok == false
    doAssert     patt({'a','b'}).match("a").ok
    doAssert     patt({'a','b'}).match("b").ok
    doAssert     patt({'a','b'}).match("c").ok == false
    doAssert     patt({'a'..'c'}).match("a").ok
    doAssert     patt({'a'..'c'}).match("b").ok
    doAssert     patt({'a'..'c'}).match("c").ok
    doAssert     patt({'a'..'c'}).match("d").ok == false
    doAssert     patt({'a'..'c'}).match("a").ok
    doAssert     patt("").match("abcde").matchLen == 0
    doAssert     patt("a").match("abcde").matchLen == 1
    doAssert     patt("ab").match("abcde").matchLen == 2
    doassert     patt(i"ab").match("AB").ok

  test "?: zero or one":
    doAssert     patt("a" * ?"b" * "c").match("abc").ok
    doAssert     patt("a" * ?"b" * "c").match("ac").ok

  test "+: one or more":
    doAssert     patt("a" * +"b" * "c").match("abc").ok
    doAssert     patt("a" * +"b" * "c").match("abbc").ok
    doAssert     patt("a" * +"b" * "c").match("ac").ok == false

  test "*: zero or more":
    doAssert     patt(*'a').match("aaaa").ok
    doAssert     patt(*'a' * 'b').match("aaaab").ok
    doAssert     patt(*'a' * 'b').match("bbbbb").ok
    doAssert     patt(*'a' * 'b').match("caaab").ok == false
    doAssert     patt(+'a' * 'b').match("aaaab").ok
    doAssert     patt(+'a' * 'b').match("ab").ok
    doAssert     patt(+'a' * 'b').match("b").ok == false

  test "!: not predicate":
    doAssert     patt('a' * !'b').match("ac").ok
    doAssert     patt('a' * !'b').match("ab").ok == false

  test "&: and predicate":
    doAssert     patt(&"abc").match("abc").ok
    doAssert     patt(&"abc").match("abd").ok == false
    doAssert     patt(&"abc").match("abc").matchLen == 0

  test "@: search":
    doAssert     patt(@"fg").match("abcdefghijk").matchLen == 7

  test "[n]: count":
    doAssert     patt(1[3]).match("aaaa").ok
    doAssert     patt(1[4]).match("aaaa").ok
    doAssert     patt(1[5]).match("aaaa").ok == false

  test "[m..n]: count":
    doAssert     patt('a'[5]).match("aaaa").ok == false
    doAssert     patt('a'[2..4]).match("a").ok == false
    doAssert     patt('a'[2..4]).match("aa").ok
    doAssert     patt('a'[2..4]).match("aaa").ok
    doAssert     patt('a'[2..4]).match("aaaa").ok
    doAssert     patt('a'[2..4]).match("aaaaa").ok
    doAssert     patt('a'[2..4]).match("aaaab").ok

  test "|: ordered choice":
    doAssert     patt("ab" | "cd").match("ab").ok
    doAssert     patt("ab" | "cd").match("cd").ok
    doAssert     patt("ab" | "cd").match("ef").ok == false

  test "-: difference":
    doAssert     patt("abcd" - "abcdef").match("abcdefgh").ok == false
    doAssert     patt("abcd" - "abcdf").match("abcdefgh").ok

  test "Builtins":
    doAssert     patt(Digit).match("1").ok
    doAssert     patt(Digit).match("a").ok == false
    doAssert     patt(Upper).match("A").ok
    doAssert     patt(Upper).match("a").ok == false
    doAssert     patt(Lower).match("a").ok
    doAssert     patt(Lower).match("A").ok == false
    doAssert     patt(+Digit).match("12345").ok
    doAssert     patt(+Xdigit).match("deadbeef").ok
    doAssert     patt(+Graph).match(" x").ok == false

  test "Compile time":
    proc dotest(): string {.compileTime.} =
      var n: string
      let p = peg "number":
        number <- >+Digit:
          n = $1
      doAssert p.match("12345").ok
      return n
    const v = doTest()
    doAssert v == "12345"

  test "grammar1":
    let a = peg "r1":
      r1 <- "abc"
      r2 <- r1 * r1
    doAssert a.match("abcabc").ok

  test "grammar2":
    let a = peg "r1":
      r2 <- r1 * r1
      r1 <- "abc"
    doAssert a.match("abcabc").ok
  
  test "backref":
    doAssert patt(Ref("sep", Alpha) * *(1 - Backref("sep")) * Backref("sep") * !1).match("abbbba").ok
    doAssert patt(Ref("sep", Alpha) * *(1 - Backref("sep")) * Backref("sep") * !1).match("abbbbc").ok == false

  test "raise exception 1":
    let a = patt E"boom"
    expect NPegException:
      doAssert a.match("abcabc").ok

  test "raise exception 2":
    let a = patt 4 * E"boom"
    try:
      doAssert a.match("abcabc").ok
    except NPegException:
      let e = (ref NPegException)getCurrentException()
      doAssert e.matchLen == 4
      doAssert e.matchMax == 4

