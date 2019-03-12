
# NPeg

NPeg is an early stage pure Nim pattern-matching library.


## Grammar


```
 Atoms:
    '.'           literal character
    "..."         literal string
   i"..."         case insensitive string
    _             matches any character
    {}            empty set, always matches
    {'x'..'y'}    range from 'x' to 'y', inclusive
    {'x','y'}     set
  
 Grammar rules:
   (P)            grouping
   -P             matches everything but P
    P1 * P2       concatenation
    P1 | P2       ordered choice
    P1 - P2       matches P1 if P1 does not match
   ?P             conditional, 0 or 1 times
   *P             0 or more times P
   +P             1 or more times P
    P{n}          exactly n times P
    P{m..n}       m to n times p
```


## Examples

Parsing HTTP requests:
    
let data = """
POST flop HTTP/1.1
content-length: 23
Content-Type: text/plain
"""

```nim
let match = peg "http":
  space                 <- ' '
  crlf                  <- '\n' | "\r\n"
  version               <- "1.0" | "1.1"
  alpha                 <- {'a'..'z','A'..'Z'}
  digit                 <- {'0'..'9'}
  
  meth                  <- "GET" | "POST" | "PUT"
  proto                 <- "HTTP"

  url                   <- +alpha

  req                   <- meth * space * url * space * proto * "/" * version * crlf

  header_content_length <- i"Content-Length: " * +digit
  header_other          <- +(alpha | '-') * ": "
  header                <- header_content_length | header_other

  http                  <- req * *header

match data

```

Parsing simple expressions with proper operator precedence:


```nim
let match = peg "line":
  ws       <- *' '
  digit    <- {'0'..'9'}
  number   <- +digit * ws
  termOp   <- {'+', '-'} * ws
  factorOp <- {'*', '/'} * ws
  open     <- '(' * ws
  close    <- ')' * ws
  exp      <- term * *(termOp * term)
  term     <- factor * *(factorOp * factor)
  factor   <- number | open * exp * close
  line     <- ws * exp

match "13 + 5 * (1+3) / 7"
```

