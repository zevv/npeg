
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
    "json": 0.712,
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
    Value          <- S * ( Number | String | Object | Array | True | False | Null ) * S
    ObjPair        <- S * String * S * ":" * Value
    Object         <- '{' * ( ObjPair * *( "," * ObjPair ) | S ) * "}"
    Array          <- "[" * ( Value * *( "," * Value ) | S ) * "]"

    JSON           <- Value * !1

  for i in 1..10:
    doAssert p.match(js).ok


let s = newStringStream(js)
measureTime "parsejson":
  # JSon parsing with nims 'parsejson' module.
  for i in 1..10:
    s.setPosition(0)
    var p: JsonParser
    open(p, s, "json")
    while true:
      p.next()
      if p.kind == jsonError or p.kind == jsonEof:
        break


measureTime "words":

  var v = 0
  let p = peg foo:
    foo <- +word
    word <- @>+Alpha:
      inc v
  discard p.match(js).ok


measureTime "search":
  # Search using built in search operator
  var v = 0
  let p = peg search:
    search <- @"CALIFORNIA":
      inc v
  for i in 1..10:
    discard p.match(js).ok


measureTime "search1":
  # Searches using tail recursion.
  let p = peg SS:
    SS <- +S
    S <- "CALIFORNIA" | 1 * S
  for i in 1..10:
    discard p.match(js).ok

measureTime "search2":
  # Searches using an explicit
  let p = peg SS:
    SS <- +S
    S <- *( !"CALIFORNIA" * 1) * "CALIFORNIA"
  for i in 1..10:
    discard p.match(js).ok

measureTime "search3":
   # using an optimization to skip false starts.
  let p = peg SS:
    SS <- +S
    S <- "CALIFORNIA" | 1 * *(1-'C') * S
  for i in 1..10:
    discard p.match(js).ok

