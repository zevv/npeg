import unittest
import npeg
  
{.push warning[Spacing]: off.}

const verbose = false
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
    doAssert     patt(_{3})("aaaa")
    doAssert     patt(_{4})("aaaa")
    doAssert not patt('a'{5})("aaaa")
    doAssert not patt('a'{2..4})("a")
    doAssert     patt('a'{2..4})("aa")
    doAssert     patt('a'{2..4})("aaa")
    doAssert     patt('a'{2..4})("aaaa")
    doAssert     patt('a'{2..4})("aaaaa")
    doAssert     patt('a'{2..4})("aaaab")
    doAssert     patt('a'{2-4})("aaaab")

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

  test "simple examples":

    let p1 = patt +{'a'..'z'}
    doAssert p1("lowercaseword")

    let p2 = peg "ident":
      lower <- {'a'..'z'}
      ident <- +lower
    doAssert p2("lowercaseword")

  test "DFA":

    # Check for an even number of 0s and 1s
    #
    #  ->1 <---0---> 2
    #    ^           ^
    #    |           |
    #    1           1
    #    |           |
    #    V           V
    #    3 <---0---> 4

    let s = peg "P1":
      P1 <- '0' * P2 | '1' * P3 | !1
      P2 <- '0' * P1 | '1' * P4
      P3 <- '0' * P4 | '1' * P1
      P4 <- '0' * P3 | '1' * P2
    doAssert     s("00110011")
    doAssert not s("0011001101100111")
    doAssert     s("0011001101100110")

  test "HTTP parser":


    let data ="""
POST flop HTTP/1.1
Content-Type: text/plain
content-length: 23
"""
    let s = peg "http":
      space                 <- ' '
      crlf                  <- '\n' | "\r\n"
      meth                  <- "GET" | "POST" | "PUT"
      proto                 <- "HTTP"
      version               <- "1.0" | "1.1"
      alpha                 <- {'a'..'z','A'..'Z'}
      digit                 <- {'0'..'9'}
      url                   <- +alpha
      eof                   <- !1

      req                   <- meth * space * url * space * proto * "/" * version

      header_content_length <- i"Content-Length: " * +digit
      header_other          <- +(alpha | '-') * ": " * +(_-crlf)
    
      header                <- header_content_length | header_other
      http                  <- req * crlf * *(header * crlf) * eof

    doAssert s(data)


  test "expression parser":

    let s = peg "line":
      ws       <- *' '
      digit    <- {'0'..'9'} * ws
      number   <- +digit * ws
      termOp   <- {'+', '-'} * ws
      factorOp <- {'*', '/'} * ws
      open     <- '(' * ws
      close    <- ')' * ws
      eol      <- !1
      exp      <- term * *(termOp * term)
      term     <- factor * *(factorOp * factor)
      factor   <- number | (open * exp * close)
      line     <- ws * exp * eol

    doAssert s "1"
    doAssert s "1+1"
    doAssert s "1+1*1"
    doAssert s "(1+1)*1"
    doAssert s "13 + 5 * (2+1)"


  test "JSON parser":

    let json = """
      {
          "glossary": {
              "title": "example glossary",
              "GlossDiv": {
                  "title": "S",
                  "GlossList": {
                      "GlossEntry": {
                          "ID": "SGML",
                              "SortAs": "SGML",
                              "GlossTerm": "Standard Generalized Markup Language",
                              "Acronym": "SGML",
                              "Abbrev": "ISO 8879:1986",
                              "GlossDef": {
                              "para": "A meta-markup language, used to create markup languages such as DocBook.",
                              "GlossSeeAlso": ["GML", "XML"]
                          },
                          "GlossSee": "markup"
                      }
                  }
              }
          }
      }
      """

    let s = peg "DOC":
      S              <- *{' ','\t','\r','\n'}
      True           <- "true"
      False          <- "false"
      Null           <- "null"

      UnicodeEscape  <- 'u' * {'0'..'9','A'..'F','a'..'f'}{4}
      Escape         <- '\\' * ({ '{', '"', '|', '\\', 'b', 'f', 'n', 'r', 't' } | UnicodeEscape)
      StringBody     <- ?Escape * *( +( {'\x20'..'\xff'} - {'"'} - {'\\'}) * *Escape) 
      String         <- ?S * '"' * StringBody * '"' * ?S

      Minus          <- '-'
      IntPart        <- '0' | {'1'..'9'} * *{'0'..'9'}
      FractPart      <- "." * +{'0'..'9'}
      ExpPart        <- ( 'e' | 'E' ) * ?( '+' | '-' ) * +{'0'..'9'}
      Number         <- ?Minus * IntPart * ?FractPart * ?ExpPart

      DOC            <- JSON * !1
      JSON           <- ?S * ( Number | Object | Array | String | True | False | Null ) * ?S
      Object         <- '{' * ( String * ":" * JSON * *( "," * String * ":" * JSON ) | ?S ) * "}"
      Array          <- "[" * ( JSON * *( "," * JSON ) | ?S ) * "]"

    doAssert s(json)

