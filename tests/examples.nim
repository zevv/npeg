import unittest
import npeg
import json
import strutils
import tables
import npeg/lib/uri

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

  test "shadowing":
    
    let parser = peg "line":
      line <- uri.URI
      uri.scheme <- >uri.scheme
      uri.host <- >uri.host
      uri.port <- >+Digit
      uri.path <- >uri.path
    
    let r = parser.match("http://nim-lang.org:8080/one/two/three")
    doAssert r.captures == @["http", "nim-lang.org", "8080", "/one/two/three"]

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

    let s = peg(Request, "http"):
      space       <- ' '
      crlf        <- '\n' * ?'\r'
      url         <- +(Alpha | Digit | '/' | '_' | '.')
      eof         <- !1
      header_name <- +(Alpha | '-')
      header_val  <- +(1-{'\n'}-{'\r'})
      proto       <- >(+Alpha):
        userdata.proto = $1
      version     <- >(+Digit * '.' * +Digit):
        userdata.version = $1
      code        <- >+Digit:
        userdata.code = parseInt($1)
      msg         <- >(+(1 - '\r' - '\n')):
        userdata.message = $1
      header      <- >header_name * ": " * >header_val:
        userdata.headers[$1] = $2

      response    <- proto * '/' * version * space * code * space * msg 
      headers     <- *(header * crlf)
      http        <- response * crlf * headers * eof

    let data = """
HTTP/1.1 301 Moved Permanently
Content-Length: 162
Content-Type: text/html
Location: https://nim.org/
"""

    var req: Request
    let res = s.match(data, req)
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
      doc <- +word * "<<" * R("sep", sep) * S * >heredoc * R("sep") * S * +word
      word <- +Alpha * S
      sep <- +Alpha
      heredoc <- +(1 - R("sep"))

    let d = """This is a <<EOT here document
    with multiple lines EOT end"""

    let r = p.match(d)
    doAssert r.ok
    doAssert r.captures[0] == "here document\n    with multiple lines "

  ######################################################################
  
  test "RFC3986: Uniform Resource Identifier (URI): Generic Syntax":

    type Uri = object
      scheme: string
      userinfo: string
      host: string
      path: string
      port: string
      query: string
      fragment: string

    # The grammar below is a literal translation of the ABNF notation of the
    # RFC. Optimizations can be made to limit backtracking, but this is a nice
    # example how to create a parser from a RFC protocol description.

    let p = peg(Uri, "URI"):

      URI <- scheme * ":" * hier_part * ?( "?" * query) * ?( "#" * fragment) * !1

      hier_part <- "//" * authority * path_abempty |
                   path_absolute |
                   path_rootless |
                   path_empty

      URI_reference <- uri | relative_ref

      absolute_uri <- scheme * ":" * hier_part * ?( "?" * query)

      relative_ref <- relative_part * ?( "?" * query) * ?( "#" * fragment)

      relative_part <- "//" * authority * path_abempty |
                       path_absolute |
                       path_noscheme |
                       path_empty

      scheme <- >(Alpha * *( Alpha | Digit | "+" | "-" | "." )): userdata.scheme = $1

      authority <- ?(userinfo * "@") * host * ?( ":" * port)
      userinfo <- >*(unreserved | pct_encoded | sub_delims | ":"):
        userdata.userinfo = $1

      host <- >(IP_literal | IPv4address | reg_name): userdata.host = $1
      port <- >*Digit: userdata.port = $1

      IP_literal <- "[" * (IPv6address | IPvFuture) * "]"

      IPvFuture <- "v" * +Xdigit * "." * +(unreserved | sub_delims | ":")

      IPv6address <-                                     (h16 * ":")[6] * ls32 |
                                                  "::" * (h16 * ":")[5] * ls32 |
                   ?( h16                     ) * "::" * (h16 * ":")[4] * ls32 |
                   ?( h16 * (":" * h16)[0..1] ) * "::" * (h16 * ":")[3] * ls32 |
                   ?( h16 * (":" * h16)[0..2] ) * "::" * (h16 * ":")[2] * ls32 |
                   ?( h16 * (":" * h16)[0..3] ) * "::" * (h16 * ":")    * ls32 |
                   ?( h16 * (":" * h16)[0..4] ) * "::" *                  ls32 |
                   ?( h16 * (":" * h16)[0..5] ) * "::" *                  h16  |
                   ?( h16 * (":" * h16)[0..6] ) * "::"

      h16 <- Xdigit[1..4]
      ls32 <- (h16 * ":" * h16) | IPv4address
      IPv4address <- dec_octet * "." * dec_octet * "." * dec_octet * "." * dec_octet

      dec_octet <- Digit                   | # 0-9
                  {'1'..'9'} * Digit       | # 10-99
                  "1" * Digit * Digit      | # 100-199
                  "2" * {'0'..'4'} * Digit | # 200-249
                  "25" * {'0'..'5'}          # 250-255

      reg_name <- *(unreserved | pct_encoded | sub_delims)

      path <- path_abempty  | # begins with "/" or is empty
              path_absolute | # begins with "/" but not "//"
              path_noscheme | # begins with a non-colon segment
              path_rootless | # begins with a segment
              path_empty      # zero characters

      path_abempty  <- >(*( "/" * segment )): userdata.path = $1
      path_absolute <- >("/" * ?( segment_nz * *( "/" * segment ) )): userdata.path = $1
      path_noscheme <- >(segment_nz_nc * *( "/" * segment )): userdata.path = $1
      path_rootless <- >(segment_nz * *( "/" * segment )): userdata.path = $1
      path_empty    <- 0

      segment       <- *pchar
      segment_nz    <- +pchar
      segment_nz_nc <- +( unreserved | pct_encoded | sub_delims | "@" )
                    # non_zero_length segment without any colon ":"

      pchar         <- unreserved | pct_encoded | sub_delims | ":" | "@"

      query         <- >*( pchar | "|" | "?" ): userdata.query = $1

      fragment      <- >*( pchar | "|" | "?" ): userdata.fragment = $1

      pct_encoded   <- "%" * Xdigit * Xdigit

      unreserved    <- Alpha | Digit | "-" | "." | "_" | "~"
      reserved      <- gen_delims | sub_delims
      gen_delims    <- ":" | "|" | "?" | "#" | "[" | "]" | "@"
      sub_delims    <- "!" | "$" | "&" | "'" | "(" | ")" | "*" | "+" | "," | ";" | "="

    let urls = @[
      "s3://somebucket/somefile.txt",
      "scheme://user:pass@xn--mgbh0fb.xn--kgbechtv",
      "scheme://user:pass@host:81/path?query#fragment",
      "ScheMe://user:pass@HoSt:81/path?query#fragment",
      "scheme://HoSt:81/path?query#fragment",
      "scheme://@HoSt:81/path?query#fragment",
      "scheme://user:pass@host/path?query#fragment",
      "scheme://user:pass@host:/path?query#fragment",
      "scheme://host/path?query#fragment",
      "scheme://10.0.0.2/p?q#f",
      "scheme://[vAF.1::2::3]/p?q#f",
      "scheme:path?query#fragment",
      "scheme:///path?query#fragment",
      "scheme://[FEDC:BA98:7654:3210:FEDC:BA98:7654:3210]?query#fragment",
      "scheme:path#fragment",
      "scheme:path?#fragment",
      "ldap://[2001:db8::7]/c=GB?objectClass?one",
      "http://example.org/hello:12?foo=bar#test",
      "android-app://org.wikipedia/http/en.m.wikipedia.org/wiki/The_Hitchhiker%27s_Guide_to_the_Galaxy",
      "ftp://:/p?q#f",
      "scheme://user:pass@host:000000000081/path?query#fragment",
      "scheme://user:pass@host:81/path?query#fragment",
      "ScheMe://user:pass@HoSt:81/path?query#fragment",
      "scheme://HoSt:81/path?query#fragment",
      "scheme://@HoSt:81/path?query#fragment",
      "scheme://user:pass@host/path?query#fragment",
      "scheme://user:pass@host:/path?query#fragment",
      "scheme://user:pass@host/path?query#fragment",
      "scheme://host/path?query#fragment",
      "scheme://10.0.0.2/p?q#f",
      "scheme:path?query#fragment",
      "scheme:///path?query#fragment",
      "scheme://[FEDC:BA98:7654:3210:FEDC:BA98:7654:3210]?query#fragment",
      "scheme:path#fragment",
      "scheme:path?#fragment",
      "tel:05000",
      "scheme:path#",
      "https://thephpleague.com./p?#f",
      "http://a_.!~*\'(-)n0123Di%25%26:pass;:&=+$,word@www.zend.com",
      "http://",
      "http:::/path",
      "ldap://[2001:db8::7]/c=GB?objectClass?one",
      "http://example.org/hello:12?foo=bar#test",
      "android-app://org.wikipedia/http/en.m.wikipedia.org/wiki/The_Hitchhiker%27s_Guide_to_the_Galaxy",
      "scheme://user:pass@xn--mgbh0fb.xn--kgbechtv",
      "http://download.linuxjournal.com/pdf/get-doc.php?code=2c230d54e20e7cb595c660da48be7622&tcode=epub-301-"
    ]

    for s in urls:
      var uri: Uri
      let r = p.match(s, uri)
      if not r.ok:
        echo s
        quit 1
