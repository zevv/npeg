import unittest
import npeg
import json
  
{.push warning[Spacing]: off.}
abortOnError = true


suite "npeg":

  test "simple examples":

    let p1 = patt +{'a'..'z'}
    doAssert p1("lowercaseword").ok

    let p2 = peg "ident":
      lower <- {'a'..'z'}
      ident <- +lower
    doAssert p2("lowercaseword").ok


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

    doAssert s("1").ok
    doAssert s("1+1").ok
    doAssert s("1+1*1").ok
    doAssert s("(1+1)*1").ok
    doAssert s("13 + 5 * (2+1)").ok


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

    doAssert s(json).ok

  test "HTTP with captures":
    let s = peg "http":
      space       <- ' '
      crlf        <- '\n' * ?'\r'
      alpha       <- {'a'..'z','A'..'Z'}
      digit       <- {'0'..'9'}
      url         <- +(alpha | digit | '/' | '_' | '.')
      eof         <- !1
      header_name <- +(alpha | '-')
      header_val  <- +(1-{'\n'}-{'\r'})
      proto       <- Cn("proto", C(+alpha) )
      version     <- Cn("version", C(+digit * '.' * +digit) )
      code        <- Cn("code", C(+digit) )
      msg         <- Cn("msg", C(+(1 - '\r' - '\n')) )
      header      <- Ca( C(header_name) * ": " * C(header_val) )

      response    <- Cn("response", Co( proto * '/' * version * space * code * space * msg ))
      headers     <- Cn("headers", Ca( *(header * crlf) ))
      http        <- Co(response * crlf * headers * eof)

    let data = """
HTTP/1.1 301 Moved Permanently
Content-Length: 162
Content-Type: text/html
Location: https://nim.org/
"""

    let res = s(data)
    doAssert res.ok
    doAssert res.capturesJson == parseJson("""{"response":{"proto":"HTTP","version":"1.1","code":"301","msg":"Moved Permanently"},"headers":[["Content-Length","162"],["Content-Type","text/html"],["Location","https://nim.org/"]]}""")


