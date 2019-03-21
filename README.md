
# NPeg

NPeg is a pure Nim pattern-matching library. It provides macros to compile
patterns and grammars (PEGs) to Nim procedures which will parse a string and collect
selected parts of the input.

```nim
import npeg, strutils, tables

var words = initTable[string, int]()

let match = peg "pairs":
  pairs <- pair * *(',' * pair) * !1
  word <- +{'a'..'z'}
  number <- +{'0'..'9'}
  pair <- (>word * '=' * >number) % (words[c[0]] = parseInt(c[1]))

doAssert match("one=1,two=2,three=3,four=4").ok
echo words

{"two": 2, "three": 3, "one": 1, "four": 4}
```

Npeg can generate parsers that run at compile time.


## Usage

The `patt()` and `peg()` macros can be used to compile parser functions.

`patt()` can create a parser from a single anonymouse pattern, while `peg()`
allows the definion of a set of (potentially recursive) rules making up a
complete grammar.

The result of these macros is a parser function that can be called to parse a
subject string. The parser function returns an object of the type `MatchResult`:

```nim
MatchResult = object
  ok: bool                   # Set to 'true' if the string parsed without errors
  matchLen: int              # The length up to where the string was parsed.
```

The following proc are available to retrieve the captured results:

```nim
proc captures(m: MatchResult): seq[string]
proc capturesJson(m: MatchResult): JsonNode
```


### Simple patterns

A simple pattern can be compiled with the `patt` macro:

```nim
let p = patt *{'a'..'z'}
doAssert p("lowercaseword").ok
```

### Grammars

The `peg` macro provides a method to define (recursive) grammars. The first
argument is the name of initial patterns, followed by a list of named patterns.
Patterns can now refer to other patterns by name, allowing for recursion:

```nim
let p = peg "ident":
  lower <- {'a'..'z'}
  ident <- *lower
doAssert p("lowercaseword").ok
```


#### Ordering of rules in a grammar

The order in which the grammar patterns are defined affects the generated parser.
Although NPeg could aways reorder, this is a design choice to give the user
more control over the generated parser:

* when a pattern `P1` refers to pattern `P2` which is defined *before* `P1`,
  `P2` will be inlined in `P1`.  This increases the generated code size, but
  generally improves performance.

* when a pattern `P1` refers to pattern `P2` which is defined *after* `P1`,
  `P2` will be generated as a subroutine which gets called from `P1`. This will
  reduce code size, but might also result in a slower parser.

The exact parser size and performance behavior depends on many factors; when
performance and/or code size matters, it pays to experiment with different
orderings and measure the results.



## Syntax

NPeg patterns and grammars can be composed from the following parts:


### Atoms

```nim
  0            # matches always and consumes nothing
  1            # matches any character
  n            # matches exactly n characters
 'x'           # matches literal character 'x'
 "xyz"         # matches literal string "xyz"
i"xyz"         # matches literal string, case insensitive
 {'x'..'y'}    # matches any character in the range from 'x'..'y'
 {'x','y','z'} # matches any character from the set
```

The set syntax `{}` is flexible and can take multiple ranges and characters in
one expression, for example `{'0'..'9','a'..'f','A'..'F'}`.


### Operators

```nim
(P)            # grouping
!P             # matches everything but P.
 P1 * P2       # concatenation
 P1 | P2       # ordered choice
 P1 - P2       # matches P1 if P2 does not match
?P             # matches P zero or one times
*P             # matches P zero or more times
+P             # matches P one or more times
 P{n}          # matches P n times
 P{m..n}       # matches P m to n times
```

### Captures

String capture:

```nim
>P             # Captures the string matching P
```

Json captures:

```nim
Js(P)          # Produces a JString from the string matching P
Ji(P)          # Produces a JInteger from the string matching P
Jf(P)          # Produces a JFloat from the string matching P
Ja()           # Produces a new JArray
Jo()           # Produces a new JObject
Jt("tag", P)   # Stores capture P in the field "tag" of the outer JObject
Jt(P)          # Stores the second Json capture of P in the outer JObject,
               # using the first Json capure of P as the tag. 
```

Action capture:

```nim
P % code       # Passes all matches made in P to the code fragment
               # in the variable c: seq[string]
```


## Searching

Patterns are always matched in anchored mode only. To search for a pattern in
a stream, a construct like this can be used:

```nim
p <- "hello"
search <- p | 1 * search
```

The above grammar first tries to match pattern `p`, or if that fails, matches
any character `1` and recurses back to itself.



## Captures

NPeg supports a number of ways to capture data when parsing a string. The various
capture methods are described here, including a concise example.

The capture examples below build on the following small PEG, which parses
a comma separated list of key-value pairs:

```nim
const data = "one=1,two=2,three=3,four=4"

let s = peg "pairs":
  pairs <- pair * *(',' * pair) * !1
  word <- +{'a'..'z'}
  pair <- word * '=' * word
```

### String captures

The basic method for capturing is marking parts of the peg
with the capture prefix `>`. During parsing NPeg keeps track of all matches,
properly discarting any matches which were invalidated by backtracking. Only
when parsing has fully succeeded it creates a `seq[string]` of all matched
parts, which is then returned in the `MatchData.captures` field.

In the example, we add the `>` capture prefix to the `word` rule, causing all
the matched words to be added to the result capture `seq[string]`

```nim
let s = peg "pairs":
  pairs <- pair * *(',' * pair) * !1
  word <- +{'a'..'z'}
  pair <- >word * '=' * >word
```

The resultings list of captures ia now:

```nim
@["one", "1", "two", "2", "three", "3", "four", "4"]
```


### JSON captures

In order capture more complex data it is possible to mark the PEG with
operators which will build a tree of JsonNodes from the matched data.

In the example below: 

- The outermost rule `pairs` gets encapsulated by the `Jo` operator, which
  produces a javascript object (`JObject`).

- The `pair` rule is encapsulated in `Jt` which will produce a tagged pair
  which will be stored in its outer JObject. 

- The matched `word` is captured with `Js` to produce a JString. This will
  be consumed by its outer `Jt` capure which will used it for the field name

- The matched `number` is captured with a `Ji` to produce a JInteger, which
  will be consumed by its outer `Jt` capture which will use it for the field
  value.

```nim
let s = peg "pairs":
  pairs <- Jo(pair * *(',' * pair) * !1)
  word <- +{'a'..'z'}
  number <- +{'0'..'9'}
  pair <- Jt(Js(word) * '=' * Ji(number))
```

The resulting Json data is now:

```json
{
  "one": 1,
  "two": 2,
  "three": 3,
  "four": 4
}
```


### Action captures

The `%` operator can be used to execute arbritary Nim code during parsing. The
Nim code can access all captures made within the the capture through the
implicit declared variable `c: seq[string]`. Note that the Nim code gets
excuted during parsing, *even if the match is part of a pattern that fails and
is later backtracked*

The example has been extended to capture each word and number with the regular `>` capture
prefix. Then the complete pair is passed to a snippet of Nim code by the `%` operator,
where the data is added to a Nim table:

```nim
from strutils import parseInt
var words = initTable[string, int]()

let s = peg "pairs":
  pairs <- pair * *(',' * pair) * !1
  word <- +{'a'..'z'}
  number <- +{'0'..'9'}
  pair <- (>word * '=' * >number) % (words[c[0]] = parseInt(c[1])) 
```

After the parsing finished, the `words` table will now contain

```nim
{"two": 2, "three": 3, "one": 1, "four": 4}
```

Note: Due to ambiguities in the PEG syntax, the code on the right hand of the `%`
might not be parsed right at compile time, especially when this is an assignment
statement - simple enclose the statement in brackets to mitigate.


## Error handling

The `ok` field in the `MatchResult` indicates if the parser was successful. The
`matchLen` field indicates how to which offset the matcher was able to parse
the subject string. If matching fails, `matchLen` is usually a good indication
of where in the subject string the error occured.


## NPeg vs PEG

The NPeg syntax is similar to normal PEG notation, but some changes were made
to allow the grammar to be properly parsed by the Nim compiler:

- NPeg uses prefixes instead of suffixes for `*`, `+`, `-` and `?`
- Ordered choice uses `|` instead of `/` because of operator precedence
- The explict `*` infix operator is used for sequences


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


## Tracing and debugging

When compiled with `-d:npegTrace`, NPeg will dump its immediate representation
of the compiled PEG, and will dump a trace of the execution during matching.
These traces can be used for debugging purposes or for performance tuning of
the parser. This is considered advanced use, and the exact interpretation of
the trace is not discussed here.

For example, the following program:

```nim
let s2 = peg "line":
  line <- ("one" | "two") * "three"
discard s2("twothree")
```

will output the following output:

```
0: opChoice 3
1: opStr one
2: opCommit 4
3: opStr two
4: opStr three
5: opReturn

  0 |   0 |twothree  | choice -> 3  |
  1 |   0 |twothree  | str one      | *   (ip: 3, si: 0, rp: 0, cp: 0)
  3 |   0 |twothree  | fail -> 3    |
  3 |   0 |twothree  | str two      |
  4 |   3 |three     | str three    |
  5 |   8 |          | return       |
  5 |   8 |          | done         |
```


## Examples

### Parsing mathematical expressions

```nim
let s = peg "line":
  exp      <- term   * *( ('+'|'-') * term)
  term     <- factor * *( ('*'|'/') * factor)
  factor   <- +{'0'..'9'} | ('(' * exp * ')')
  line     <- exp * !1

doAssert s("3*(4+15)+2").ok
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

  DOC            <- JSON * !1
  JSON           <- ?S * ( Number | Object | Array | String | True | False | Null ) * ?S
  Object         <- '{' * ( String * ":" * JSON * *( "," * String * ":" * JSON ) | ?S ) * "}"
  Array          <- "[" * ( JSON * *( "," * JSON ) | ?S ) * "]"

let doc = """ {"jsonrpc": "2.0", "method": "subtract", "params": [42, 23], "id": 1} """
doAssert match(doc).ok
```


### Captures

The following example shows captures in action. This PEG parses a HTTP
request into a nested JSON tree:

```nim
let s = peg "http":
  space       <- ' '
  crlf        <- '\n' * ?'\r'
  alpha       <- {'a'..'z','A'..'Z'}
  digit       <- {'0'..'9'}
  url         <- +(alpha | digit | '/' | '_' | '.')
  eof         <- !1
  header_name <- +(alpha | '-')
  header_val  <- +(1-{'\n'}-{'\r'})
  proto       <- Cn("proto", C(+alpha) )
  version     <- Cn("version", C(+digit * '.' * +digit) )
  code        <- Cn("code", C(+digit) )
  msg         <- Cn("msg", C(+(1 - '\r' - '\n')) )
  header      <- Ca( C(header_name) * ": " * C(header_val) )

  response    <- Cn("response", Co( proto * '/' * version * space * code * space * msg ))
  headers     <- Cn("headers", Ca( *(header * crlf) ))
  http        <- Co(response * crlf * headers * eof)

let data = """
HTTP/1.1 301 Moved Permanently
Content-Length: 162
Content-Type: text/html
Location: https://nim.org/
"""

let r = s(data)
echo r.capturesJson.pretty
```


The resulting JSON data:
```json
{
  "response": {
    "proto": "HTTP",
    "version": "1.1",
    "code": "301",
    "msg": "Moved Permanently"
  },
  "headers": [
    [
      "Content-Length",
      "162"
    ], [
      "Content-Type",
      "text/html"
    ], [
      "Location",
      "https://nim.org/"
    ]
  ]
}
```

