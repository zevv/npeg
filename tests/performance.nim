
import npeg
import os
import streams
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
    "json": 0.651,
    "parsejson": 3.962,
    "words": 0.920,
    "search": 0.057,
    "search1": 0.231,
    "search2": 1.419,
    "search3": 0.292,
  }.toTable(),
  "fe2": { 
    "json": 3.975,
    "parsejson": 8.739,
    "words": 2.391,
    "search": 0.373,
    "search1": 2.014,
    "search2": 2.871,
    "search3": 0.771,
  }.toTable(),
}.toTable()


# Wake up the governor a bit

var v = 0
for i in 1..100000:
  for j in 1..1000000:
    inc v


template measureTime*(what: string, code: untyped) =

  var expect = 0.0
  if hostname in expectTime:
    if what in expectTime[hostname]:
      expect = expectTime[hostname][what]

  let start = cpuTime()
  block:
    code
  let duration = cpuTime() - start
  let perc = 100.0 * duration / expect
  echo what & ": ", duration.formatFloat(ffDecimal, 3), "s ", perc.formatFloat(ffDecimal, 1), "%"


measureTime "json":

  ## Json parsing with npeg

  let p = peg JSON:
    S              <- *{' ','\t','\r','\n'}
    True           <- "true"
    False          <- "false"
    Null           <- "null"

    UnicodeEscape  <- 'u' * Xdigit[4]
    Escape         <- '\\' * ({ '"', '\\', '/', 'b', 'f', 'n', 'r', 't' } | UnicodeEscape)
    StringBody     <- *Escape * *( +( {'\x20'..'\xff'} - {'"'} - {'\\'}) * *Escape) 
    String         <- '"' * StringBody * '"'

    Minus          <- '-'
    IntPart        <- '0' | {'1'..'9'} * *{'0'..'9'}
    FractPart      <- "." * +{'0'..'9'}
    ExpPart        <- ( 'e' | 'E' ) * ?( '+' | '-' ) * +{'0'..'9'}
    Number         <- ?Minus * IntPart * ?FractPart * ?ExpPart

    DOC            <- Value * !1
    ObjPair        <- S * String * S * ":" * Value
    Object         <- '{' * ( ObjPair * *( "," * ObjPair ) | S ) * "}"
    Array          <- "[" * ( Value * *( "," * Value ) | S ) * "]"
    Value          <- S * ( Number | String | Object | Array | True | False | Null ) * S

    JSON           <- Value * !1

  for i in 1..10:
    doAssert p.match(js).ok

