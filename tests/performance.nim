
import npeg
import os
import strutils
import tables
import json
import times
import packedjson
import osproc

let js = execProcess("bzip2 -d < tests/json-32M.bzip2").string

let hostname = readFile("/etc/hostname").strip()

let expectTime = {
  "platdoos": { 
    "json": 0.165,
    "words": 1.05,
    "search": 0.34,
  }.toTable()
}.toTable()


template measureTime*(what: string, code: untyped) =

  var expect = 0.0
  if hostname in expectTime:
    expect = expectTime[hostname][what]

  let start = cpuTime()
  block:
    code
  let duration = cpuTime() - start
  let perc = 100.0 * duration / expect
  echo what & ": ", duration.formatFloat(ffDecimal, 3), "s ", perc.formatFloat(ffDecimal, 1), "%"


measureTime "json":

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


measureTime "words":

  var v = 0
  let p = peg foo:
    foo <- +word
    word <- @>+Alpha:
      inc v
  discard p.match(js).ok


measureTime "search":

  var v = 0
  let p = peg search:
    search <- @"CALIFORNIA":
      inc v
  for i in 1..10:
    discard p.match(js).ok

