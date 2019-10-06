
import npeg
import os
import strutils
import json
import times
import packedjson
import osproc

let js = execProcess("bzip2 -d < tests/json-32M.bzip2").string

template measureTime*(what: string, expect: float, code: untyped) =
  let start = cpuTime()
  block:
    code
  let duration = cpuTime() - start
  echo what & ": ", duration.formatFloat(ffDecimal, 3), "s ", (duration/expect).formatFloat(ffDecimal, 3)


measureTime "json", 0.165:

  let p = peg "JSON":
    S              <- *{' ','\t','\r','\n'}
    True           <- "true"
    False          <- "false"
    Null           <- "null"

    UnicodeEscape  <- 'u' * {'0'..'9','A'..'F','a'..'f'}[4]
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

  echo p.match(js)


measureTime "words", 2.20:

  var v = 0
  let p = peg foo:
    foo <- +word
    word <- @>+Alpha:
      inc v
  discard p.match(js).ok


measureTime "search", 0.34:

  var v = 0
  let p = peg search:
    search <- @"CALIFORNIA":
      inc v
  for i in 1..10:
    discard p.match(js).ok

