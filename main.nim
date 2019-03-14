
import npeg
import os
import json



when true:

  let data ="""
HTTP/2.0 304 Not Modified
date: Thu, 14 Mar 2019 19:55:21 GMT
last-modified: Fri, 01 Feb 2019 11:20:09 GMT
etag: "5c542b69-e1ffd"
expires: Thu, 14 Mar 2019 19:55:20 GMT
cache-control: no-cache
expect-ct: max-age=604800, report-uri="https://report-uri.cloudflare.com/cdn-cgi/beacon/expect-ct"
server: cloudflare
cf-ray: 4b78ce02a9c7c82d-AMS
"""

  let s2 = peg "http":
    space                 <- ' '
    crlf                  <- '\n' * ?'\r'
    proto                 <- "HTTP"
    version               <- +digit * '.' * +digit
    alpha                 <- ['a'-'z','A'-'Z']
    digit                 <- ['0'-'9']
    url                   <- +(alpha | digit | '/' | '_' | '.')
    eof                   <- ![]

    code                  <- C(+digit)
    msg                   <- +([] - '\r' - '\n')
    response              <- proto * '/' * version * space * code * space * msg 
    header                <- header_content_length | header_other
    http                  <- response * crlf * *(header * crlf) * eof

    header_content_length <- i"Content-Length: " * +digit
    header_other          <- +(alpha | '-') * ": " * +([]-['\n']-['\r'])


  let (ok, pos, caps) = s2(data)
  echo ok
  echo pos
  echo caps

