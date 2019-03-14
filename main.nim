
import npeg
import os
import json

proc doe(s: string) =
  echo "DOE ", s

let s = patt "a" * Cp(doe, "b")
echo s("ab")

when true:

  let data ="""
POST flop HTTP/1.1
Content-Type: text/plain
content-length: 23
"""

  let s2 = peg "http":
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

  doAssert s2(data)

