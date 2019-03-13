import unittest
import npeg
  
const verbose = false
abortOnError = true


suite "npeg":

  test "atoms":
    doAssert patt("a")("a")
    doAssert not patt("a")("b")
    doAssert patt("abc")("abc")
    doAssert patt(['a'])("a")
    doAssert not patt(['a'])("b")
    doAssert patt(['a','b'])("a")
    doAssert patt(['a','b'])("b")
    doAssert not patt(['a','b'])("c")

  test "simple examples":

    let p1 = patt *['a'..'z']
    doAssert p1("lowercaseword")

    let p2 = peg "ident":
      lower <- ['a'..'z']
      ident <- *lower
    doAssert p2("lowercaseword")

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
      alpha                 <- ['a'..'z','A'..'Z']
      digit                 <- ['0'..'9']
      url                   <- +alpha
      eof                   <- -[]

      req                   <- meth * space * url * space * proto * "/" * version

      header_content_length <- i"Content-Length: " * +digit
      header_other          <- +(alpha | '-') * ": " * +([]-crlf)
    
      header                <- header_content_length | header_other
      http                  <- req * crlf * *(header * crlf) * eof

    doAssert s(data)


  test "expression parser":

    let s = peg "line":
      ws       <- *' '
      digit    <- ['0'..'9'] * ws
      number   <- +digit * ws
      termOp   <- ['+', '-'] * ws
      factorOp <- ['*', '/'] * ws
      open     <- '(' * ws
      close    <- ')' * ws
      eol      <- -[]
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
      S              <- *[' ','\t','\r','\n']
      String         <- ?S * '"' * *(['\x20'..'\xff'] - '"' - '\\' | Escape ) * '"' * ?S
      Escape         <- '\\' * ([ '[', '"', '|', '\\', 'b', 'f', 'n', 'r', 't' ] | UnicodeEscape)
      UnicodeEscape  <- 'u' * ['0'..'9','A'..'F','a'..'f']{4}
      True           <- "true"
      False          <- "false"
      Null           <- "null"
      Number         <- ?Minus * IntPart * ?FractPart * ?ExpPart
      Minus          <- '-'
      IntPart        <- '0' | ['1'..'9'] * *['0'..'9']
      FractPart      <- "." * +['0'..'9']
      ExpPart        <- ( 'e' | 'E' ) * ?( '+' | '-' ) * +['0'..'9']
      DOC            <- JSON * -[]
      JSON           <- ?S * ( Number | Object | Array | String | True | False | Null ) * ?S
      Object         <- '{' * ( String * ":" * JSON * *( "," * String * ":" * JSON ) | ?S ) * "}"
      Array          <- "[" * ( JSON * *( "," * JSON ) | ?S ) * "]"

    doAssert s(json)

