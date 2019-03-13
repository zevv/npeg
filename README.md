
# NPeg

NPeg is an early stage pure Nim pattern-matching library. It provides macros to compile
patterns and grammars to Nim procedures which will parse a string.


## Simple patterns

A simple pattern can be compiled with the `patt` macro:

```
let p = patt *{'a'..'z'}
assert p("lowercaseword")
```

The `peg` macro provides a method to define (recursive) grammars. The first
argument is the name of initial rule, followed by a list of named patterns:

```
let p = peg "ident":
  lower <- {'a'..'z'}
  ident <- *lower
doAssert p("lowercaseword")
``
assert p("lowercaseword")


## Grammar

Npeg patterns can be composed from the following parts:

```
 Atoms:
    'x'           matches literal character 'x'
    "xyz"         matches literal string "xyz"
   i"xyz"         matches literal string, case insensitive
    {}            matches any character
    {'x'..'y'}    matches any character in the range from 'x'..'y'
    {'x','y','z'} matches any character from the set

 Grammar rules:
   (P)            grouping
   -P             matches everything but P
    P1 * P2       concatenation
    P1 | P2       ordered choice
    P1 - P2       matches P1 if P2 does not match
   ?P             matches P 0 or 1 times
   *P             matches P 0 or more times
   +P             matches P 1 or more times P
    P{n}          matches P n times
    P{m..n}       matches P m to n times
```



## Examples

Parsing HTTP requests:

```nim

let data = """
POST flop HTTP/1.1
Content-length: 23
User-Agent: curl/7.64.0
Content-Type: text/plain
"""

let match = peg "http":
  space                 <- ' '
  crlf                  <- '\n' | "\r\n"
  meth                  <- "GET" | "POST" | "PUT"
  proto                 <- "HTTP"
  version               <- "1.0" | "1.1"
  alpha                 <- {'a'..'z','A'..'Z'}
  digit                 <- {'0'..'9'}
  url                   <- +alpha
  eof                   <- -{}

  req                   <- meth * space * url * space * proto * "/" * version

  header_content_length <- i"Content-Length: " * +digit
  header_other          <- +(alpha | '-') * ": " * +({}-crlf)

  header                <- header_content_length | header_other
  http                  <- req * crlf * *(header * crlf) * eof

doAssert match(data)

```


A complete JSON parser:

```nim

let match = peg "DOC":
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

let doc = """ {"jsonrpc": "2.0", "method": "subtract", "params": [42, 23], "id": 1} """
doAssert match(doc)
```



