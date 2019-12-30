import unittest
import strutils
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
    doAssert     patt('a'[2..4] * !1).match("").ok == false
    doAssert     patt('a'[2..4] * !1).match("a").ok == false
    doAssert     patt('a'[2..4] * !1).match("aa").ok
    doAssert     patt('a'[2..4] * !1).match("aaa").ok
    doAssert     patt('a'[2..4] * !1).match("aaaa").ok
    doAssert     patt('a'[2..4] * !1).match("aaaaa").ok == false

    doAssert     patt('a'[0..1] * !1).match("").ok
    doAssert     patt('a'[0..1] * !1).match("a").ok
    doAssert     patt('a'[0..1] * !1).match("aa").ok == false

  test "|: ordered choice":
    doAssert     patt("ab" | "cd").match("ab").ok
    doAssert     patt("ab" | "cd").match("cd").ok
    doAssert     patt("ab" | "cd").match("ef").ok == false
    doAssert     patt(("ab" | "cd") | "ef").match("ab").ok == true
    doAssert     patt(("ab" | "cd") | "ef").match("cd").ok == true
    doAssert     patt(("ab" | "cd") | "ef").match("ef").ok == true
    doAssert     patt("ab" | ("cd") | "ef").match("ab").ok == true
    doAssert     patt("ab" | ("cd") | "ef").match("cd").ok == true
    doAssert     patt("ab" | ("cd") | "ef").match("ef").ok == true

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

  test "Misc combos":
    doAssert     patt('a' | ('b' * 'c')).match("a").ok
    doAssert     patt('a' | ('b' * 'c') | ('d' * 'e' * 'f')).match("a").ok
    doAssert     patt('a' | ('b' * 'c') | ('d' * 'e' * 'f')).match("bc").ok
    doAssert     patt('a' | ('b' * 'c') | ('d' * 'e' * 'f')).match("def").ok

  test "Compile time 1":
    proc dotest(): string {.compileTime.} =
      var n: string
      let p = peg "number":
        number <- >+Digit:
          n = $1
      doAssert p.match("12345").ok
      return n
    const v = doTest()
    doAssert v == "12345"

  test "Compile time 2":
    static:
      var n: string
      let p = peg "number":
        number <- >+Digit:
          n = $1
      doAssert p.match("12345").ok
      doAssert n == "12345"

  test "matchMax":
    let s = peg "line":
      line   <- one | two
      one    <- +Digit * 'c' * 'd' * 'f'
      two    <- +Digit * 'b'
    let r = s.match("1234cde")
    doAssert r.ok == false
    doAssert r.matchLen == 4
    doAssert r.matchMax == 6

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
    doAssert patt(R("sep", Alpha) * *(1 - R("sep")) * R("sep") * !1).match("abbbba").ok
    doAssert patt(R("sep", Alpha) * *(1 - R("sep")) * R("sep") * !1).match("abbbbc").ok == false

  test "raise exception 1":
    let a = patt E"boom"
    expect NPegException:
      doAssert a.match("abcabc").ok

  test "raise exception 2":
    let a = patt 4 * E"boom"
    try:
      doAssert a.match("abcabc").ok
    except NPegException as e:
      doAssert e.matchLen == 4
      doAssert e.matchMax == 4

  test "out of range capture exception 1":
    expect NPegException:
      let a = patt 1:
        echo capture[10].s
      doAssert a.match("c").ok

  test "out of range capture exception 2":
    expect NPegException:
      let a = patt 1:
        echo $9
      doAssert a.match("c").ok

  test "user validation":
    let p = peg "line":
      line <- uint8 * "," * uint8 * !1
      uint8 <- >+Digit:
        let v = parseInt($1)
        validate(v>=0 and v<=255)
    doAssert p.match("10,10").ok
    doAssert p.match("0,255").ok
    doAssert not p.match("10,300").ok
    doAssert not p.match("300,10").ok

  test "user fail":
    let p = peg "line":
      line <- 1:
        fail()
    doAssert not p.match("a").ok

  test "templates":
    let p = peg "a":
      list(patt, sep) <- patt * *(sep * patt)
      commaList(patt) <- list(patt, ",")
      a <- commaList(>+Digit)
    doAssert p.match("11,22,3").captures == ["11","22","3"]

  test "templates with choices":
    let p = peg aap:
      one() <- "one"
      two() <- "one"
      three() <- "flip" | "flap"
      aap <- one() | two() | three()
    doAssert p.match("onetwoflip").ok

