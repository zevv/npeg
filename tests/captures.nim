import unittest
import npeg
import strutils
import json
  
{.push warning[Spacing]: off.}


suite "captures":

  test "string captures":
    doAssert     patt(>1).match("ab").captures == @["a"]
    doAssert     patt(>(>1)).match("ab").captures == @["a", "a"]
    doAssert     patt(>1 * >1).match("ab").captures == @["a", "b"]
    doAssert     patt(>(>1 * >1)).match("ab").captures == @["ab", "a", "b"]
    doAssert     patt(>(>1 * >1)).match("ab").captures == @["ab", "a", "b"]

  test "code block captures":
    var a: string
    let p = peg "foo":
      foo <- >1:
        a = $1
    doAssert p.match("a").ok
    doassert a == "a"

  test "code block captures 2":
    let p = peg("foo", v: string):
      foo <- >1: v = $1
    var a: string
    doAssert p.match("a", a).ok
    doassert a == "a"
  
  test "code block captures 3":
    var a: string
    let p = patt >1:
        a = $1
    doAssert p.match("a").ok
    doassert a == "a"

  test "code block captures with typed parser":

    type Thing = object
      word: string
      number: int

    let s = peg("foo", t: Thing):
      foo <- word * number
      word <- >+Alpha:
        t.word = $1
      number <- >+Digit:
        t.number = parseInt($1)

    var t = Thing()
    doAssert s.match("foo123", t).ok == true
    doAssert t.word == "foo"
    doAssert t.number == 123

  test "Capture out of range":
    expect NPegException:
      let p = peg "l":
        l <- 1: echo $1
      discard p.match("a")

  test "push":
    let p = peg "m":
      m <- >n * '+' * >n:
        push $(parseInt($1) + parseInt($2))
      n <- +Digit
    let r = p.match("12+34")
    doAssert r.captures()[0] == "46"
  
  test "nested":
    doAssert patt(>(>1 * >1)).match("ab").captures == @["ab", "a", "b"]

  test "nested codeblock":
    let p = peg foo:
      foo <- >(>1 * b)
      b <- >1: push $1
    doAssert p.match("ab").captures() == @["ab", "a", "b"]
