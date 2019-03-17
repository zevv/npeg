import unittest
import npeg
import json
  
{.push warning[Spacing]: off.}
abortOnError = true


suite "npeg":

  test "atoms":
    doAssert     patt(0 * "a")("a")
    doAssert     patt(1)("a")
    doAssert     patt(1)("a")
    doAssert not patt(2)("a")
    doAssert     patt("a")("a")
    doAssert not patt("a")("b")
    doAssert     patt("abc")("abc")
    doAssert     patt({'a'})("a")
    doAssert not patt({'a'})("b")
    doAssert     patt({'a','b'})("a")
    doAssert     patt({'a','b'})("b")
    doAssert not patt({'a','b'})("c")
    doAssert     patt({'a'..'c'})("a")
    doAssert     patt({'a'..'c'})("b")
    doAssert     patt({'a'..'c'})("c")
    doAssert not patt({'a'..'c'})("d")
    doAssert     patt({'a'..'c'})("a")

  test "not":
    doAssert     patt('a' * !'b')("ac")
    doAssert not patt('a' * !'b')("ab")

  test "count":
    doAssert     patt(1{3})("aaaa")
    doAssert     patt(1{4})("aaaa")
    doAssert not patt('a'{5})("aaaa")
    doAssert not patt('a'{2..4})("a")
    doAssert     patt('a'{2..4})("aa")
    doAssert     patt('a'{2..4})("aaa")
    doAssert     patt('a'{2..4})("aaaa")
    doAssert     patt('a'{2..4})("aaaaa")
    doAssert     patt('a'{2..4})("aaaab")

  test "repeat":
    doAssert     patt(*'a')("aaaa")
    doAssert     patt(*'a' * 'b')("aaaab")
    doAssert     patt(*'a' * 'b')("bbbbb")
    doAssert not patt(*'a' * 'b')("caaab")
    doAssert     patt(+'a' * 'b')("aaaab")
    doAssert     patt(+'a' * 'b')("ab")
    doAssert not patt(+'a' * 'b')("b")

  test "choice":
    doAssert     patt("ab" | "cd")("ab")
    doAssert     patt("ab" | "cd")("cd")
    doAssert not patt("ab" | "cd")("ef")


