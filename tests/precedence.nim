import unittest
import strutils
import math
import npeg

{.push warning[Spacing]: off.}


suite "precedence operator":

  test "expr evaluator":

    let p = peg(exp, st: seq[int]):
      S <- *' '

      number <- +Digit * ?( "." * *Digit)

      atom <- >number * S: st.add parseInt($1)

      uniminus <- >'-' * exp: st.add(-st.pop)

      parenExp <- ( "(" * exp * ")" ) ^ 0

      prefix <- atom | parenExp | uniminus | E"atom"

      postfix <- >("or"|"xor") * exp ^ 3 |
                 >("and")      * exp ^ 4 |
                 >{'+','-'}    * exp ^ 8 |
                 >{'*','/'}    * exp ^ 9 |
                 >{'^'}        * exp ^^ 10:

        let (f2, f1) = (st.pop, st.pop)
        case $1
          of "+": st.add(f1 + f2)
          of "*": st.add(f1 * f2)
          of "-": st.add(f1 - f2)
          of "/": st.add(f1 /% f2)
          of "or": st.add(f1 or f2)
          of "xor": st.add(f1 xor f2)
          of "and": st.add(f1 and f2)
          of "^": st.add(f1 ^ f2)

      exp <- S * prefix * *postfix

    proc eval(expr: string): int =
      var st: seq[int]
      doAssert p.match(expr, st).ok
      st[0]

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

