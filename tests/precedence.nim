import unittest
import strutils
import math
import tables
import npeg

{.push warning[Spacing]: off.}


suite "precedence operator":

  # The PEG below implements a Pratt parser. The ^ and ^^ operators are used to
  # implement precedence climbing, this allows rules to be left recursive while
  # still avoiding unbound recursion.
  #
  # The parser local state `seq[int]` is used as a stack to store captures and
  # intermediate results while parsing, the end result of the expression will
  # be available in element 0 when the parser finishes

  test "expr evaluator":

    # Table of binary operators - this maps the operator string to a proc
    # performing the operation:

    template map(op: untyped): untyped = (proc(a, b: int): int = op(a, b))

    var binOps = {
      "+": map(`+`),
      "-": map(`-`),
      "*": map(`*`),
      "/": map(`/%`),
      "^": map(`^`),
    }.toTable()

    let p = peg(exp, st: seq[int]):

      S <- *Space

      # Capture a number and put it on the stack

      number <- >+Digit * S:
        st.add parseInt($1)

      # Reset the precedence level to 0 when parsing sub-expressions
      # in parentheses

      parenExp <- ( "(" * exp * ")" ) ^ 0

      # Unary minues: take last element of the stack, negate and push back

      uniMinus <- '-' * exp:
        st.add(-st.pop)

      # The prefix is a number, a sub expression in parentheses or the unary
      # `-` operator.

      prefix <- number | parenExp | uniMinus

      # Parse an infix operator. Bounded by the precedece operator that makes
      # sure `exp` is only parsed if the currrent precedence is lower then the
      # given precedence. Note that the power operator has right assosiativity.

      infix <- >{'+','-'}    * exp ^  1 |
               >{'*','/'}    * exp ^  2 |
               >{'^'}        * exp ^^ 3 :

        # Takes two results off the stack, applies the operator and push
        # back the result

        let (f2, f1) = (st.pop, st.pop)
        st.add binOps[$1](f1, f2)

      # An expression consists of a prefix followed by zero or more infix
      # operators

      exp <- S * prefix * *infix


    # Evaluate the given expression

    proc eval(expr: string): int =
      var st: seq[int]
      doAssert p.match(expr, st).ok
      st[0]


    # Test cases

    doAssert eval("2+1") == 2+1
    doAssert eval("(((2+(1))))") == 2+1
    doAssert eval("3+2") == 3+2

    doAssert eval("3+2+4") == 3+2+4
    doAssert eval("(3+2)+4") == 3+2+4
    doAssert eval("3+(2+4)") == 3+2+4
    doAssert eval("(3+2+4)") == 3+2+4

    doAssert eval("3*2*4") == 3*2*4
    doAssert eval("(3*2)*4") == 3*2*4
    doAssert eval("3*(2*4)") == 3*2*4
    doAssert eval("(3*2*4)") == 3*2*4

    doAssert eval("3-2-4") == 3-2-4
    doAssert eval("(3-2)-4") == (3-2)-4
    doAssert eval("3-(2-4)") == 3-(2-4)
    doAssert eval("(3-2-4)") == 3-2-4

    doAssert eval("3/8/4") == 3/%8/%4
    doAssert eval("(3/8)/4") == (3/%8)/%4
    doAssert eval("3/(8/4)") == 3/%(8/%4)
    doAssert eval("(3/8/4)") == 3/%8/%4

    doAssert eval("(3*8/4)") == 3*8/%4
    doAssert eval("(3/8*4)") == 3/%8*4
    doAssert eval("3*(8/4)") == 3*(8/%4)

    doAssert eval("4^3^2") == 4^3^2
    doAssert eval("(4^3)^2") == (4^3)^2
    doAssert eval("4^(3^2)") == 4^(3^2)

