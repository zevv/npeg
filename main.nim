
import npeg
import os
import json


let s = peg "wot":
  a <- "hello"
  wot <- a | [] * wot

echo s("dit is hello ja daag")


when false:

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
    header_name <- +(alpha | '-')
    header_val  <- +([]-['\n']-['\r'])
  
    proto       <- Cf( "proto", +alpha )
    version     <- Cf( "version", +digit * '.' * +digit )
    code        <- Cf( "code", +digit )
    msg         <- Cf( "msg", +([] - '\r' - '\n') )
    response    <- Co( proto * '/' * version * space * code * space * msg )
    header      <- Ca( C(header_name) * ": " * C(header_val) )
    headers     <- Ca( *(header * crlf) )
    http        <- response * crlf * headers * eof
  
  var captures = newJArray()
  doAssert s2(data, captures)
  echo captures.pretty
  
