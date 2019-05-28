import unittest
import npeg
import json
import strutils
import tables

{.push warning[Spacing]: off.}


suite "examples":

  ######################################################################

  test "misc":

    let p1 = patt +{'a'..'z'}
    doAssert p1.match("lowercaseword").ok

    let p2 = peg "ident":
      lower <- {'a'..'z'}
      ident <- +lower
    doAssert p2.match("lowercaseword").ok

  ######################################################################

  test "matchFile":

    when defined(windows) or defined(posix):

      let parser = peg "pairs":
        pairs <- pair * *(',' * pair)
        word <- +Alnum
        number <- +Digit
        pair <- (>word * '=' * >number)

      let r = parser.matchFile "tests/testdata"
      doAssert r.ok
      doAssert r.captures == @["one", "1", "two", "2", "three", "3", "four", "4"]

  ######################################################################

  test "expression parser":

    let s = peg "line":
      ws       <- *' '
      number   <- +Digit * ws
      termOp   <- {'+', '-'} * ws
      factorOp <- {'*', '/'} * ws
      open     <- '(' * ws
      close    <- ')' * ws
      eol      <- !1
      exp      <- term * *(termOp * term)
      term     <- factor * *(factorOp * factor)
      factor   <- number | (open * exp * close)
      line     <- ws * exp * eol

    doAssert s.match("1").ok
    doAssert s.match("1+1").ok
    doAssert s.match("1+1*1").ok
    doAssert s.match("(1+1)*1").ok
    doAssert s.match("13 + 5 * (2+1)").ok

  ######################################################################

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

    let s = peg "doc":
      S              <- *Space
      jtrue          <- "true"
      jfalse         <- "false"
      jnull          <- "null"

      unicodeEscape  <- 'u' * Xdigit[4]
      escape         <- '\\' * ({ '{', '"', '|', '\\', 'b', 'f', 'n', 'r', 't' } | unicodeEscape)
      stringBody     <- ?escape * *( +( {'\x20'..'\xff'} - {'"'} - {'\\'}) * *escape) 
      jstring        <- ?S * '"' * stringBody * '"' * ?S

      minus          <- '-'
      intPart        <- '0' | (Digit-'0') * *Digit
      fractPart      <- "." * +Digit
      expPart        <- ( 'e' | 'E' ) * ?( '+' | '-' ) * +Digit
      jnumber        <- ?minus * intPart * ?fractPart * ?expPart

      doc            <- JSON * !1
      JSON           <- ?S * ( jnumber | jobject | jarray | jstring | jtrue | jfalse | jnull ) * ?S
      jobject        <- '{' * ( jstring * ":" * JSON * *( "," * jstring * ":" * JSON ) | ?S ) * "}"
      jarray         <- "[" * ( JSON * *( "," * JSON ) | ?S ) * "]"

    doAssert s.match(json).ok

  ######################################################################

  test "HTTP with action captures to Nim object":

    type
      Request = object
        proto: string
        version: string
        code: int
        message: string
        headers: Table[string, string]

    var req: Request
    req.headers = initTable[string, string]()

    let s = peg "http":
      space       <- ' '
      crlf        <- '\n' * ?'\r'
      url         <- +(Alpha | Digit | '/' | '_' | '.')
      eof         <- !1
      header_name <- +(Alpha | '-')
      header_val  <- +(1-{'\n'}-{'\r'})
      proto       <- >(+Alpha):
        req.proto = $1
      version     <- >(+Digit * '.' * +Digit):
        req.version = $1
      code        <- >+Digit:
        req.code = parseInt($1)
      msg         <- >(+(1 - '\r' - '\n')):
        req.message = $1
      header      <- >header_name * ": " * >header_val:
        req.headers[$1] = $2

      response    <- proto * '/' * version * space * code * space * msg 
      headers     <- *(header * crlf)
      http        <- response * crlf * headers * eof

    let data = """
HTTP/1.1 301 Moved Permanently
Content-Length: 162
Content-Type: text/html
Location: https://nim.org/
"""

    let res = s.match(data)
    doAssert res.ok
    doAssert req.proto == "HTTP"
    doAssert req.version == "1.1"
    doAssert req.code == 301
    doAssert req.message == "Moved Permanently"
    doAssert req.headers["Content-Length"] == "162"
    doAssert req.headers["Content-Type"] == "text/html"
    doAssert req.headers["Location"] == "https://nim.org/"

  ######################################################################

  test "HTTP capture to Json":
    let s = peg "http":
      space       <- ' '
      crlf        <- '\n' * ?'\r'
      url         <- +(Alpha | Digit | '/' | '_' | '.')
      eof         <- !1
      header_name <- +(Alpha | '-')
      header_val  <- +(1-{'\n'}-{'\r'})
      proto       <- Jf("proto", Js(+Alpha) )
      version     <- Jf("version", Js(+Digit * '.' * +Digit) )
      code        <- Jf("code", Ji(+Digit) )
      msg         <- Jf("msg", Js(+(1 - '\r' - '\n')) )
      header      <- Ja( Js(header_name) * ": " * Js(header_val) )

      response    <- Jf("response", Jo( proto * '/' * version * space * code * space * msg ))
      headers     <- Jf("headers", Ja( *(header * crlf) ))
      http        <- Jo(response * crlf * headers * eof)

    let data = """
HTTP/1.1 301 Moved Permanently
Content-Length: 162
Content-Type: text/html
Location: https://nim.org/
"""

    let res = s.match(data)
    doAssert res.ok
    doAssert res.capturesJson == parseJson("""{"response":{"proto":"HTTP","version":"1.1","code":301,"msg":"Moved Permanently"},"headers":[["Content-Length","162"],["Content-Type","text/html"],["Location","https://nim.org/"]]}""")

  ######################################################################

  test "UTF-8":

    let b = "  añyóng  ♜♞♝♛♚♝♞♜ оживлённым   "

    let m = peg "s":

      cont <- {128..191}

      utf8 <- {0..127} |
              {194..223} * cont[1] |
              {224..239} * cont[2] |
              {240..244} * cont[3]

      s <- *(@ > +(utf8-' '))

    let r = m.match(b)
    doAssert r.ok
    let c = r.captures
    doAssert c == @["añyóng", "♜♞♝♛♚♝♞♜", "оживлённым"]

  ######################################################################

  test "Back references":

    let p = peg "doc":
      S <- *Space
      doc <- +word * "<<" * Ref("sep", sep) * S * >heredoc * Backref("sep") * S * +word
      word <- +Alpha * S
      sep <- +Alpha
      heredoc <- +(1 - Backref("sep"))

    let d = """This is a <<EOT here document
    with multiple lines EOT end"""

    let r = p.match(d)
    doAssert r.ok
    doAssert r.captures[0] == "here document\n    with multiple lines "


