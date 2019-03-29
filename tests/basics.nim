import unittest
import npeg
  
{.push warning[Spacing]: off.}


suite "unit tests":

  test "atoms":
    doAssert     patt(0 * "a").match("a").ok
    doAssert     patt(1).match("a").ok
    doAssert     patt(1).match("a").ok
    doAssert not patt(2).match("a").ok
    doAssert     patt("a").match("a").ok
    doAssert not patt("a").match("b").ok
    doAssert     patt("abc").match("abc").ok
    doAssert     patt({'a'}).match("a").ok
    doAssert not patt({'a'}).match("b").ok
    doAssert     patt({'a','b'}).match("a").ok
    doAssert     patt({'a','b'}).match("b").ok
    doAssert not patt({'a','b'}).match("c").ok
    doAssert     patt({'a'..'c'}).match("a").ok
    doAssert     patt({'a'..'c'}).match("b").ok
    doAssert     patt({'a'..'c'}).match("c").ok
    doAssert not patt({'a'..'c'}).match("d").ok
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
    doAssert not patt("a" * +"b" * "c").match("ac").ok

  test "*: zero or more":
    doAssert     patt(*'a').match("aaaa").ok
    doAssert     patt(*'a' * 'b').match("aaaab").ok
    doAssert     patt(*'a' * 'b').match("bbbbb").ok
    doAssert not patt(*'a' * 'b').match("caaab").ok
    doAssert     patt(+'a' * 'b').match("aaaab").ok
    doAssert     patt(+'a' * 'b').match("ab").ok
    doAssert not patt(+'a' * 'b').match("b").ok

  test "!: not predicate":
    doAssert     patt('a' * !'b').match("ac").ok
    doAssert not patt('a' * !'b').match("ab").ok

  test "&: and predicate":
    doAssert     patt(&"abc").match("abc").ok
    doAssert not patt(&"abc").match("abd").ok
    doAssert     patt(&"abc").match("abc").matchLen == 0

  test "@: search":
    doAssert     patt(@"fg").match("abcdefghijk").matchLen == 7

  test "{n}: count":
    doAssert     patt(1[3]).match("aaaa").ok
    doAssert     patt(1[4]).match("aaaa").ok

  test "{m..n}: count":
    doAssert not patt('a'[5]).match("aaaa").ok
    doAssert not patt('a'[2..4]).match("a").ok
    doAssert     patt('a'[2..4]).match("aa").ok
    doAssert     patt('a'[2..4]).match("aaa").ok
    doAssert     patt('a'[2..4]).match("aaaa").ok
    doAssert     patt('a'[2..4]).match("aaaaa").ok
    doAssert     patt('a'[2..4]).match("aaaab").ok

  test "|: ordered choice":
    doAssert     patt("ab" | "cd").match("ab").ok
    doAssert     patt("ab" | "cd").match("cd").ok
    doAssert not patt("ab" | "cd").match("ef").ok

  test "-: difference":
    doAssert not patt("abcd" - "abcdef").match("abcdefgh").ok
    doAssert     patt("abcd" - "abcdf").match("abcdefgh").ok

  test "Builtins":
    doAssert     patt(Digit).match("1").ok
    doAssert not patt(Digit).match("a").ok
    doAssert     patt(Upper).match("A").ok
    doAssert not patt(Upper).match("a").ok
    doAssert     patt(Lower).match("a").ok
    doAssert not patt(Lower).match("A").ok
    doAssert     patt(+Digit).match("12345").ok
    doAssert     patt(+Xdigit).match("deadbeef").ok

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

  test "raise exception":
    let a = patt E"boom"
    expect NPegException:
      doAssert a.match("abcabc").ok

