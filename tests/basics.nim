import unittest
import npeg
  
{.push warning[Spacing]: off.}


suite "unit tests":

  test "atoms":
    doAssert     patt(0 * "a")("a").ok
    doAssert     patt(1)("a").ok
    doAssert     patt(1)("a").ok
    doAssert not patt(2)("a").ok
    doAssert     patt("a")("a").ok
    doAssert not patt("a")("b").ok
    doAssert     patt("abc")("abc").ok
    doAssert     patt({'a'})("a").ok
    doAssert not patt({'a'})("b").ok
    doAssert     patt({'a','b'})("a").ok
    doAssert     patt({'a','b'})("b").ok
    doAssert not patt({'a','b'})("c").ok
    doAssert     patt({'a'..'c'})("a").ok
    doAssert     patt({'a'..'c'})("b").ok
    doAssert     patt({'a'..'c'})("c").ok
    doAssert not patt({'a'..'c'})("d").ok
    doAssert     patt({'a'..'c'})("a").ok

  test "?: zero or one":
    doAssert     patt("a" * ?"b" * "c")("abc").ok
    doAssert     patt("a" * ?"b" * "c")("ac").ok

  test "+: one or more":
    doAssert     patt("a" * +"b" * "c")("abc").ok
    doAssert     patt("a" * +"b" * "c")("abbc").ok
    doAssert not patt("a" * +"b" * "c")("ac").ok

  test "*: zero or more":
    doAssert     patt(*'a')("aaaa").ok
    doAssert     patt(*'a' * 'b')("aaaab").ok
    doAssert     patt(*'a' * 'b')("bbbbb").ok
    doAssert not patt(*'a' * 'b')("caaab").ok
    doAssert     patt(+'a' * 'b')("aaaab").ok
    doAssert     patt(+'a' * 'b')("ab").ok
    doAssert not patt(+'a' * 'b')("b").ok

  test "!: not":
    doAssert     patt('a' * !'b')("ac").ok
    doAssert not patt('a' * !'b')("ab").ok

  test "@: search":
    doAssert     patt(@"fg")("abcdefghijk").matchLen == 7

  test "{n}: count":
    doAssert     patt(1{3})("aaaa").ok
    doAssert     patt(1{4})("aaaa").ok

  test "{m..n}: count":
    doAssert not patt('a'{5})("aaaa").ok
    doAssert not patt('a'{2..4})("a").ok
    doAssert     patt('a'{2..4})("aa").ok
    doAssert     patt('a'{2..4})("aaa").ok
    doAssert     patt('a'{2..4})("aaaa").ok
    doAssert     patt('a'{2..4})("aaaaa").ok
    doAssert     patt('a'{2..4})("aaaab").ok

  test "|: ordered choice":
    doAssert     patt("ab" | "cd")("ab").ok
    doAssert     patt("ab" | "cd")("cd").ok
    doAssert not patt("ab" | "cd")("ef").ok

  test "-: difference":
    doAssert not patt("abcd" - "abcdef")("abcdefgh").ok
    doAssert     patt("abcd" - "abcdf")("abcdefgh").ok

  test "grammar1":
    let a = peg "r1":
      r1 <- "abc"
      r2 <- r1 * r1
    doAssert a("abcabc").ok

  test "grammar2":
    let a = peg "r1":
      r2 <- r1 * r1
      r1 <- "abc"
    doAssert a("abcabc").ok

  test "raise exception":
    let a = patt E"boom"
    expect NPegException:
      doAssert a("abcabc").ok

