
import npeg
import os
import json



when true:

  let data ="""
HTTP/2.0 304 Not Modified
date: Thu, 14 Mar 2019 19:55:21 GMT
cache-control: no-cache
server: cloudflare
"""

let s2 = peg "http":
  space       <- ' '
  crlf        <- '\n' * ?'\r'
  alpha       <- ['a'-'z','A'-'Z']
  digit       <- ['0'-'9']
  url         <- +(alpha | digit | '/' | '_' | '.')
  eof         <- ![]
  
  proto       <- C(+alpha)
  version     <- C(+digit * '.' * +digit)
  code        <- C(+digit)
  msg         <- C(+([] - '\r' - '\n'))

  response    <- Ca(proto * '/' * version * space * code * space * msg)

  http        <- response * crlf * *(header * crlf) * eof

  header_name <- +(alpha | '-')
  header_val  <- +([]-['\n']-['\r'])
  header      <- Ca( C(header_name) * ": " * C(header_val) )


var captures = newJArray()
doAssert s2(data, captures)
echo captures.pretty

