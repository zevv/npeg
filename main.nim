
import npeg
import os
import json


let data ="""
POST flop HTTP/1.1
Content-Type: text/plain
content-length: 23
"""

proc doe(s: string) =
  echo "FLOP ", s

let s = peg "http":
  space                 <- ' '
  crlf                  <- '\n' | "\r\n"
  meth                  <- C("GET" | "POST" | "PUT")
  proto                 <- C("HTTP")
  version               <- C("1.0" | "1.1")
  alpha                 <- ['a'..'z','A'..'Z']
  digit                 <- ['0'..'9']
  url                   <- C(+alpha)
  eof                   <- -[]

  req                   <- Cp(doe, meth * space * url * space * proto * "/" * version)

  header_content_length <- i"Content-Length: " * +digit
  header_other          <- +(alpha | '-') * ": " * +([]-crlf)

  header                <- C(header_content_length | header_other)
  http                  <- req * crlf * *(header * crlf) * eof

doAssert s(data)

