import unittest
import npeg

proc doTest(p: Patt, s: string, v: bool) =
  echo "------------ '" & s & "' -----"
  echo $p
  echo "------------"
  let ok = p.match(s) == v
  if not ok:
    doAssert false
    quit 1
  echo ""

suite "npeg":


  test "basics":

    doTest(P"abc", "abc", true)
    doTest(P"abc", "def", false)
    doTest(P"abc" + P"def", "abc", true)
    doTest(P"abc" + P"def", "def", true)
    doTest(P"abc" + P"def", "boo", false)
    doTest(P"abc" * P"def", "a", false)
    doTest(P"abc" * P"def", "abc", false)
    doTest(P"abc" * P"def", "abcde", false)
    doTest(P"abc" * P"def", "abcdef", true)
    doTest(P"abc" * P"def", "abcdefg", true)
    doTest(P"ab" * P(2) * P "ef", "abcdef", true)
    doTest(S"abc", "a", true)
    doTest(S"abc", "b", true)
    doTest(S"abc", "d", false)
    doTest(S"abc" + S"ced", "a", true)
    doTest(S"abc" + S"def", "d", true)
    doTest(S"abc" + S"def", "g", false)
    doTest(P"abc" * S"def" * P"ghi", "abcdghi", true)
    doTest(P"abc" * S"def" * P"ghi", "abceghi", true)
    doTest(P"abc" * S"def" * P"ghi", "abcgghi", false)
    doTest(P"abc" * S"def" * P"ghi", "abcghi", false)
    doTest(P"abc"^0, "abcefg", true)
    doTest(P"abc"^2, "abc", false)
    doTest(P"abc"^2, "abcabc", true)
    doTest(P"abc"^2, "abcabcabc", true)
    doTest(P"abc" ^ -3, "foo", true)
    doTest(P"abc" ^ -2, "abc", true)
    doTest(P"abc" ^ -2, "abcabc", true)
    doTest(P"abc" ^ -2, "abcabcabc", true)
    doTest(P"abc" ^ -2, "abcabcabc", true)
    doTest((P"abc" ^ -2) * P"foo", "foo", true)
    doTest((P"abc" ^ -2) * P"foo", "abcfoo", true)
    doTest((P"abc" ^ -2) * P"foo", "abcabcfoo", true)
    doTest((P"abc" ^ -2) * P"foo", "abcabcabcfoo", false)
    doTest(R("az"), "a", true)
    doTest(R("az"), "b", true)
    doTest(R("az"), "z", true)
    doTest(R("az"), "A", false)

  test "stuff":

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

  test "numbers":

    let digit = R("09")

    # Matches: 10, -10, 0
    let integer =
      (S("+-") ^ -1) *
      (digit   ^  1)

    # Matches: .6, .899, .9999873
    let fractional =
      (P(".")   ) *
      (digit ^ 1)

    # Matches: 55.97, -90.8, .9 
    let decimal = 
      (integer *                     # Integer
      (fractional ^ -1)) +           # Fractional
      ((S("+-") ^ -1) * fractional)  # Completely fractional number

    # Matches: 60.9e07, 9e-4, 681E09 
    let scientific = 
      decimal * # Decimal number
      S("Ee") *        # E or e
      integer   # Exponent

    # Matches all of the above
    # Decimal allows for everything else, and scientific matches scientific
    let number = scientific + decimal

    doTest(number, "1", true)
    doTest(number, "1.0", true)
    doTest(number, "3.141592", true)
    doTest(number, "-5", true)
    doTest(number, "-5.5", true)
    doTest(number, "1e3", true)
    doTest(number, "1.0e3", true)
    doTest(number, "-1.0e-6", true)

# vim: ft=nim

