import unittest
import npeg

const verbose = false

abortOnError = true

proc doTest(p: Patt, s: string, v: bool) =
  when verbose:
    echo ""
    echo "------------ '" & s & "' -----"
    echo $p
    echo "------------"
  doAssert p.match(s, verbose) == v

suite "npeg":

  test "literal string (P)":
    doTest(P"", "abc", true)
    doTest(P"abc", "abc", true)
    doTest(P"abc", "abcde", true)
    doTest(P"abc", "qqabc", false)
    doTest(P"abc", "", false)
  
  test "literal count (P)":
    doTest(P(1), "a", true)
    doTest(P(3), "abc", true)
    doTest(P(3), "abcde", true)
    doTest(P(3), "ab", false)

  test "set (S)":
    doTest(S"quick", "", false)
    doTest(S"quick", "q", true)
    doTest(S"quick", "u", true)
    doTest(S"quick", "k", true)
    doTest(S"quick", "kkk", true)
    doTest(S"quick", "a", false)

  test "range (R)":
    doTest(R("bn"), "a", false)
    doTest(R("bn"), "b", true)
    doTest(R("bn"), "c", true)
    doTest(R("bn"), "n", true)
    doTest(R("bn"), "o", false)
    doTest(R("an", "AN"), "g", true)
    doTest(R("an", "AN"), "G", true)
    doTest(R("an", "AN"), "o", false)
    doTest(R("an", "AN"), "O", false)

  test "ordered choice / union (+)":
    doTest(P"abc" + P"def", "abc", true)
    doTest(P"abc" + P"def", "def", true)
    doTest(P"abc" + P"def", "boo", false)

  test "concatenation (*)":
    doTest(P"abc" * P"def", "a", false)
    doTest(P"abc" * P"def", "abc", false)
    doTest(P"abc" * P"def", "abcde", false)
    doTest(P"abc" * P"def", "abcdef", true)
    doTest(P"abc" * P"def", "abcdefg", true)
    doTest(P"abc" * P"def" * P"ghi", "abcdefghi", true)
    doTest(P"abc" * S"def" * P"ghi", "abcdghi", true)
    doTest(P"abc" * S"def" * P"ghi", "abceghi", true)
    doTest(P"abc" * S"def" * P"ghi", "abcgghi", false)
    doTest(P"abc" * S"def" * P"ghi", "abcghi", false)
    doTest(S"abc" + S"def", "a", true)
    doTest(S"abc" + S"def", "d", true)

  test "not (-p)":
    doTest(-P"a", "a", false)
    doTest(-P"a", "b", true)

  test "difference (-)":
    doTest(R("09") - R("04"), "0", false)
    doTest(R("09") - R("04"), "4", false)
    doTest(R("09") - R("04"), "5", true)
    doTest(R("09") - R("04"), "9", true)

  test "optional (^0)":
    doTest(P"abc"^0, "abcefg", true)
    doTest(P"abc"^0, "", true)
    doTest(P"abc"^0 * P"def", "def", true)
    doTest(P"abc" * P"def" ^ 0 * P"ghi" , "abcdefghi", true)
    doTest(P"abc" * P"def" ^ 0 * P"ghi" , "abcghi", true)

  test "repeat at least n (^n)":
    doTest(P"abc"^2, "abc", false)
    doTest(P"abc"^2, "abcabc", true)
    doTest(P"abc"^2, "abcabcabc", true)
  
  test "repeat at most n (^-n)":
    doTest(P"abc" ^ -3, "foo", true)
    doTest(P"abc" ^ -2, "abc", true)
    doTest(P"abc" ^ -2, "abcabc", true)
    doTest(P"abc" ^ -2, "abcabcabc", true)
    doTest(P"abc" ^ -2, "abcabcabc", true)
    doTest((P"abc" ^ -2) * P"foo", "foo", true)
    doTest((P"abc" ^ -2) * P"foo", "abcfoo", true)
    doTest((P"abc" ^ -2) * P"foo", "abcabcfoo", true)
    doTest((P"abc" ^ -2) * P"foo", "abcabcabcfoo", false)

  test "misc":
    doTest(P"ab" * P(2) * P "ef", "abcdef", true)
    doTest(S"abc" + S"ced", "a", true)
    doTest(S"abc" + S"def", "d", true)
    doTest(S"abc" + S"def", "g", false)

  test "example: identifiers":

    let alpha = R("az") + R("AZ")
    let digit = R("09")
    let alphanum = alpha + digit
    let underscore = P"_"
    let identifier = (alpha + underscore) * (alphanum + underscore)^0

    doTest(identifier, "foo", true)
    doTest(identifier, "foo1", true)
    doTest(identifier, "1foo", false)
    doTest(identifier, "_foo", true)
    doTest(identifier, "_1foo", true)

  test "example: matching numbers":

    let digit = R("09")

    # Matches: 10, -10, 0
    let integer =
      (S("+-") ^ -1) *
      (digit ^ 1)

    # Matches: .6, .899, .9999873
    let fractional =
      (P(".")) *
      (digit ^ 1)

    # Matches: 55.97, -90.8, .9 
    let decimal = 
      (integer * (fractional ^ -1)) + ((S("+-") ^ -1) * fractional)

    # Matches: 60.9e07, 9e-4, 681E09 
    let scientific = 
      decimal * S("Ee") * integer

    # Matches all of the above
    # Decimal allows for everything else, and scientific matches scientific
    let number = scientific + decimal

    doTest(number, "1", true)
    doTest(number, "1.0", true)
    doTest(number, "3.141592", true)
    doTest(number, "-5", true)
    doTest(number, "+5", true)
    doTest(number, "-5.5", true)
    doTest(number, "1e3", true)
    doTest(number, "1.0e3", true)
    doTest(number, "-1.0e-6", true)

# vim: ft=nim

