
import npeg
import os
import json



let s = peg "DOC":
  S              <- *{' ','\t','\r','\n'}
  String         <- ?S * '"' * *({'\x20'..'\xff'} - '"' - '\\' | Escape ) * '"' * ?S
  Escape         <- '\\' * ({ '[', '"', '|', '\\', 'b', 'f', 'n', 'r', 't' } | UnicodeEscape)
  UnicodeEscape  <- 'u' * {'0'..'9','A'..'F','a'..'f'}{4}
  True           <- "true"
  False          <- "false"
  Null           <- "null"
  Number         <- ?Minus * IntPart * ?FractPart * ?ExpPart
  Minus          <- '-'
  IntPart        <- '0' | {'1'..'9'} * *{'0'..'9'}
  FractPart      <- "." * +{'0'..'9'}
  ExpPart        <- ( 'e' | 'E' ) * ?( '+' | '-' ) * +{'0'..'9'}
  DOC            <- JSON * -{}
  JSON           <- ?S * ( Number | Object | Array | String | True | False | Null ) * ?S
  Object         <- '{' * ( String * ":" * JSON * *( "," * String * ":" * JSON ) | ?S ) * "}"
  Array          <- "[" * ( JSON * *( "," * JSON ) | ?S ) * "]"

let js = readFile"/tmp/movies.js"
#discard parsejson(js)
echo s(js)




