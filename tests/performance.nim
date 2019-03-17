
import npeg
import os
import json
import times
import packedjson
import osproc

template measureTime*(what: string, code: untyped): float =
  let start = cpuTime()
  code
  let duration = cpuTime() - start
  echo what & " took ", duration, "s"
  duration


let s = peg "JSON":
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

let js = execProcess("bzip2 -d < tests/json-32M.bzip2").string

let tNpeg = measureTime "npeg":
  echo s(js)

let tPackedJson = measureTime "packedjson":
  discard packedjson.parseJson(js)

let tJson = measureTime "json":
  discard json.parseJson(js)

doAssert tNpeg < tPAckedJson
doAssert tPackedJson < tJson
