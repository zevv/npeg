
# NPeg

NPeg is an early stage pure Nim pattern-matching library.


## Grammar


```
 Atoms:
    '.'           matches literal character
    "xyz"         matches literal string
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

match data

```

Parsing simple expressions with proper operator precedence:


```nim
let match = peg "line":
  ws       <- *' '
  digit    <- {'0'..'9'} * ws
  number   <- +digit * ws
  termOp   <- {'+', '-'} * ws
  factorOp <- {'*', '/'} * ws
  open     <- '(' * ws
  close    <- ')' * ws
  eof      <- -{}
  exp      <- term * *(termOp * term)
  term     <- factor * *(factorOp * factor)
  factor   <- number | (open * exp * close)
  line     <- ws * exp * eof

match "13 + 5 * (1+3) / 7"
```

