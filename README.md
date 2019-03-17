
# NPeg

NPeg is an early stage pure Nim pattern-matching library. It provides macros to compile
patterns and grammars to Nim procedures which will parse a string.


## Syntax

NPeg patterns can be composed from the following parts.


### Atoms

```nim
  0            # matches always and consumes nothing
  1            # matches any character
  N            # matches exactly N characters
 'x'           # matches literal character 'x'
 "xyz"         # matches literal string "xyz"
i"xyz"         # matches literal string, case insensitive
 {'x'..'y'}    # matches any character in the range from 'x'..'y'
 {'x','y','z'} # matches any character from the set
```

The set syntax `..` is flexible and can take multiple ranges and characters in
one expression, for example `{'0'..'9','a'..'f','A'..'F'}`.


### Operators

```nim
(P)            # grouping
!P             # matches everything but P.
 P1 * P2       # concatenation
 P1 | P2       # ordered choice
 P1 - P2       # matches P1 if P2 does not match
?P             # matches P 0 or 1 times
*P             # matches P 0 or more times
+P             # matches P 1 or more times
 P{n}          # matches P n times
 P{m..n}       # matches P m to n times
```


### Captures

```nim
C(P)           # Stores an anynomous capture in the open JSON array
Cn("name", P)  # Stores a named capture in the open JSON object
Ca()           # Opens a new capture JSON array []
Co()           # Opens a new capture JSON object {}
Cp(proc, P)    # Passes the captured string to procedure `proc`
```

Warning: Captures are stil in development, the interface is likely to change.

Captured data in patterns can be saved to a tree of Json nodes which can be
accessed by the application after the parsing completes. Check the examples
section below to see captures in action.


### Error handdling

```nim
E"msg"         # Throws an exception with the message "Expected E"
```

The `E"msg"` construct can be used to add error labels to a parser which will
throw an exception when reached. This can be used to provide better error
messages on parsing erors indicating what the expected element was. `E` is
typically used as the last element in an ordered choice expression that will
only be reached if all other choices failed:


```nim
s = peg "list":
  number <- +{'0'..'9'} | E"number"
  comma <- ',' | E"comma"
  list <- number * +( comma * number)
s "12,34,55"
```

## NPeg vs PEG

The NPeg syntax is similar to normal PEG notation, but some changes were made
to allow the grammar to be properly parsed by the Nim compiler:

- NPeg uses prefixes instead of suffixes for `*`, `+`, `-` and `?`
- Ordered choice uses `|` instead of `/` because of operator precedence
- The explict `*` infix operator is used for sequences


## Usage


### Simple patterns

A simple pattern can be compiled with the `patt` macro:

```nim
let p = patt *{'a'..'z'}
doAssert p("lowercaseword")
```

### Grammars

The `peg` macro provides a method to define (recursive) grammars. The first
argument is the name of initial patterns, followed by a list of named patterns.
Patterns can now refer to other patterns by name, allowing for recursion:

```nim
let p = peg "ident":
  lower <- {'a'..'z'}
  ident <- *lower
doAssert p("lowercaseword")
```


#### Searching

Patterns are always matched in anchored mode only. To search for a pattern in
a stream, a construct like this can be used:

```nim
p <- "hello"
search <- p | 1 * search
```

The above grammar first tries to match pattern `p`, or if that fails, matches
any character `1` and recurses back to itself.


#### Ordering of rules in a grammar

The order in which the grammar patterns are defined affects the generated parser.
Although NPeg could aways reorder, this is a design choice to give the user
more control over the generated parser:

* when a pattern refers to another pattern that has been defined earlier, the
  referred pattern will be inlined. This increases the code size, but generally
  improves performance.

* when a pattern refers to another pattern that has not yet been defined, the
  pattern will create a call to the referred pattern. This reduces code size, but
  might also result in a slower parser.

The exact parser size and performance behavior depends on many factors; it pays
to experiment with different orderings and measure the results.


### Limitations

NPeg does not support left recursion (this applies to PEGs in general). For
example, the rule 

```nim
A <- A / 'a'
```

will cause an infinite loop because it allows for left-recursion of the
non-terminal `A`. Similarly, the grammar

```nim
A <- B / 'a' A
B <- A is
```

is problematic because it is mutually left-recursive through the non-terminal
`B`.


Loops of patterns that can match the empty string will not result in the
expected behaviour. For example, the rule

```nim
*""
```

will cause the parser to stall and go into an infinite loop.


## Examples

### Parsing mathematical expressions

```nim
let s = peg "line":
  ws       <- *' '
  digit    <- {'0'..'9'}
  number   <- +digit * ws
  termOp   <- {'+', '-'} * ws
  factorOp <- {'*', '/'} * ws
  open     <- '(' * ws
  close    <- ')' * ws
  eol      <- !1
  exp      <- term * *(termOp * term)
  term     <- factor * *(factorOp * factor)
  factor   <- number | (open * exp * close)
  line     <- ws * exp * eol

doAssert s "3 * (4+5) + 2"
```


### A complete JSON parser

```nim
let match = peg "DOC":
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

  DOC            <- JSON * -1
  JSON           <- ?S * ( Number | Object | Array | String | True | False | Null ) * ?S
  Object         <- '{' * ( String * ":" * JSON * *( "," * String * ":" * JSON ) | ?S ) * "}"
  Array          <- "[" * ( JSON * *( "," * JSON ) | ?S ) * "]"

let doc = """ {"jsonrpc": "2.0", "method": "subtract", "params": [42, 23], "id": 1} """
doAssert match(doc)
```


### Captures

The following example shows captures in action. This PEG parses a HTTP
request into a nested JSON tree:

```nim
let s2 = peg "http":
  space       <- ' '
  crlf        <- '\n' * ?'\r'
  alpha       <- {'a'..'z','A'..'Z'}
  digit       <- {'0'..'9'}
  url         <- +(alpha | digit | '/' | '_' | '.')
  eof         <- !1
  header_name <- +(alpha | '-')
  header_val  <- +(1-{'\n'}-{'\r'})

  proto       <- Cn( "proto", +alpha )
  version     <- Cn( "version", +digit * '.' * +digit )
  code        <- Cn( "code", +digit )
  msg         <- Cn( "msg", +(1 - '\r' - '\n') )
  response    <- Co( proto * '/' * version * space * code * space * msg )
  header      <- Ca( C(header_name) * ": " * C(header_val) )
  headers     <- Ca( *(header * crlf) )
  http        <- response * crlf * headers * eof

let data = """
HTTP/1.1 301 Moved Permanently
Content-Length: 162
Content-Type: text/html
Location: https://nim.org/
"""

var captures = newJArray()
doAssert s2(data, captures)
echo captures.pretty
```

The resulting JSON data:
```json
[
  {
    "proto": "HTTP",
    "version": "1.1",
    "code": "301",
    "msg": "Moved Permanently"
  }, [
    [
      "Content-Length", "162"
    ], [
      "Content-Type", "text/html"
    ], [
      "Date", "Sun, 17 Mar 2019 10:24:35 GMT"
    ], [
      "Location", "https://nim.org/"
    ]
  ]
]
```

