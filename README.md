
# NPeg

NPeg is a pure Nim pattern-matching library. It provides macros to compile
patterns and grammars (PEGs) to Nim procedures which will parse a string and
collect selected parts of the input. PEGs are not unlike regular expressions,
but offer more power and flexibility, and have less ambiguities.

Here is a simple example showing NPegs functionality. The macro `peg` compiles
a grammar definition into a function `match`, which is used to parse a string
and place the key-value pairs into the Nim table `words`:


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

NPeg can generate parsers that run at compile time.


## Usage

The `patt()` and `peg()` macros can be used to compile parser functions.

`patt()` can create a parser from a single anonymous pattern, while `peg()`
allows the definition of a set of (potentially recursive) rules making up a
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
Although NPeg could always reorder, this is a design choice to give the user
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

The NPeg syntax is similar to normal PEG notation, but some changes were made
to allow the grammar to be properly parsed by the Nim compiler:

- NPeg uses prefixes instead of suffixes for `*`, `+`, `-` and `?`
- Ordered choice uses `|` instead of `/` because of operator precedence
- The explicit `*` infix operator is used for sequences


NPeg patterns and grammars can be composed from the following parts:

```nim
Atoms:

  0            # matches always and consumes nothing
  1            # matches any character
  n            # matches exactly n characters
 'x'           # matches literal character 'x'
 "xyz"         # matches literal string "xyz"
i"xyz"         # matches literal string, case insensitive
 {'x'..'y'}    # matches any character in the range from 'x'..'y'
 {'x','y','z'} # matches any character from the set

Operators:

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
 
Captures:

>P             # Captures the string matching P

Js(P)          # Produces a JString from the string matching P
Ji(P)          # Produces a JInteger from the string matching P
Jf(P)          # Produces a JFloat from the string matching P
Ja()           # Produces a new JArray
Jo()           # Produces a new JObject
Jt("tag", P)   # Stores capture P in the field "tag" of the outer JObject
Jt(P)          # Stores the second Json capture of P in the outer JObject,
               # using the first Json capure of P as the tag. 

P % code       # Passes all matches made in P to the code fragment
               # in the variable c: seq[string]
```

### Atoms

- Integer literal: `0` / `1` / `n`
  
  The int literal atom `N` matches exactly n number of bytes. `0` always matches,
  but does not consume any data.

- Character and string literals: `'x'` / `"xyz"` / `i"xyz"`
  
  Characters and strings are literally matched. If a string is prefixed with `i`,
  it will be matched case insensitive.

- Character sets: `{'x','y'}`
  
  Characters set notation is similar to native Nim. A set consists of zero or more
  comma separated characters or character ranges.
  
  ```nim
   {'x'..'y'}    # matches any character in the range from 'x'..'y'
   {'x','y','z'} # matches any character from the set 'x', 'y', and 'z'
  ```
  
  The set syntax `{}` is flexible and can take multiple ranges and characters in
  one expression, for example `{'0'..'9','a'..'f','A'..'F'}`.
  
  
### Operators


- Grouping: `(P)`
  
  Brackets are used to group patterns similar to normal mathematical expressions.

- Not: `!P`
  
  The pattern `!P` returns a pattern that matches only if the input does not match `P`.
  In contrast to most other patterns, this pattern does not consume any input.
  
  A common usage for this operator is the pattern `!1`, meaning "only succeed if there
  is no a single character left to match" - which is only true for the end of the string.

- Concatenation: `P1 * P2`
  
  The pattern `P1 * P2` returns a new pattern that matches only if first `P1` matches,
  followed by `P2`.
  
  For example, `"foo" * "bar"` would only match the string `"foobar"`


- Ordered choice: `P1 | P2`

  The pattern `P1 | P2` tries to first match pattern `P1`. If this succeeds, matching
  will proceed without trying `P2`. Only if `P1` can not be matched, NPeg will backtrace
  and try to match `P2`
  
  For example `("foo" | "bar") * "fizz"` would match both `"foofizz"` and `"barfizz"`
  
  NPeg optimizes the `|` operator for characters and character sets: The pattern `'a' | 'b' | 'c'`
  will be rewritten to a character set `{'a','b','c'}`


- Subtraction: `P1 - P2`

  The pattern `P1 - P2` matches `P1` *only* if `P2` does not match. This is equivalent to
`!P2 * P1`


- Match zero or one times: `?P`

  The pattern `?P` matches if `P` can be matched zero or more times, so essentially
  succeeds if `P` either matches or not.
  
  For example, `?"foo" * bar"` matches both `"foobar"` and `"bar"`


- Match zero or more times: `*P`

  The pattern `*P` tries to match as many occurrences of pattern `P` as possible.
  
  For example, `*"foo" * "bar"` matches `"bar"`, `"fooboar"`, `"foofoobar"`, etc


- Match one or more times: `+p`
  
  The pattern `+P` matches `P` at least once, but also more times. It is equivalent
  to the `P * *P`


- Match exactly `n` times: `P{n}`

  The pattern `P{n}` matches `P` exactly `n` times.
  
  For example, `"foo"{3}` only matches the string `"foofoofoo"`


- Match `m` to `n` times: `P{m..n}`
  
  The pattern `P{m..n}` matches `P` at least `m` and at most `n` times.
  
  For example, `"foo{1,3}"` matches `"foo"`, `"foofoo"` and `"foofoofo"`


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
properly discarding any matches which were invalidated by backtracking. Only
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

The resulting list of captures is now:

```nim
@["one", "1", "two", "2", "three", "3", "four", "4"]
```


### Json captures

In order capture more complex data it is possible to mark the PEG with
operators which will build a tree of JsonNodes from the matched data.

In the example below: 

- The outermost rule `pairs` gets encapsulated by the `Jo` operator, which
  produces a Json object (`JObject`).

- The `pair` rule is encapsulated in `Jt` which will produce a tagged pair
  which will be stored in its outer JObject. 

- The matched `word` is captured with `Js` to produce a JString. This will
  be consumed by its outer `Jt` capture which will used it for the field name

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

The `%` operator can be used to execute arbitrary Nim code during parsing. The
Nim code can access all captures made within the capture through the
implicit declared variable `c: seq[string]`. Note that the Nim code gets
executed during parsing, *even if the match is part of a pattern that fails and
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


## Searching

Patterns are always matched in anchored mode only. To search for a pattern in
a stream, a construct like this can be used:

```nim
p <- "hello"
search <- p | 1 * search
```

The above grammar first tries to match pattern `p`, or if that fails, matches
any character `1` and recurs back to itself.


## Error handling

The `ok` field in the `MatchResult` indicates if the parser was successful. The
`matchLen` field indicates how to which offset the matcher was able to parse
the subject string. If matching fails, `matchLen` is usually a good indication
of where in the subject string the error occurred.



## Limitations

NPeg does not support left recursion (this applies to PEGs in general). For
example, the rule 

```nim
A <- A / 'a'
```

will cause an infinite loop because it allows for left-recursion of the
non-terminal `A`. Similarly, the grammar

```nim
A <- B / 'a' A
B <- A
```

is problematic because it is mutually left-recursive through the non-terminal
`B`.


Loops of patterns that can match the empty string will not result in the
expected behaviour. For example, the rule `*0` will cause the parser to stall
and go into an infinite loop.


## Tracing and debugging

When compiled with `-d:npegTrace`, NPeg will dump its immediate representation
of the compiled PEG, and will dump a trace of the execution during matching.
These traces can be used for debugging purposes or for performance tuning of
the parser.

For example, the following program:

```nim
let s = peg "line":
  space <- ' '
  line <- word * *(space * word)
  word <- +{'a'..'z'}

discard s("one two")
```

will output the following intermediate representation at compile time.  From the
IR it can be seen that the `space` rule has been inlined in the `line` rule,
but that the `word` rule has been emitted as a subroutine which gets called
from `line`:

```
line:
  0: line           opCall         word:6
  1: line           opChoice       5
  2:  space         opStr
  3: line           opCall         word:6
  4: line           opPartCommit   2
  5:                opReturn
word:
  6: word           opSet          '{'a'-'z'}'
  7: word           opSpan         '{'a'-'z'}'
  8:                opReturn
```

At runtime, the following trace is generated. The trace consists of a number
of columns:

- 1: the current instruction pointer, which maps to the compile time dump
- 2: the index into the subject
- 3: the substring of the subject
- 4: the instruction being executed
- 5: the backtrace stack depth

```
  0 |   0 |one two       | call -> word:6      |
  6 |   0 |one two       | set {'a'-'z'}       |
  7 |   1 |ne two        | span {'a'-'z'}      |
  8 |   3 | two          | return              |
  1 |   3 | two          | choice -> 5         |
  2 |   3 | two          | str " "             | *
  3 |   4 |two           | call -> word:6      | *
  6 |   4 |two           | set {'a'-'z'}       | *
  7 |   5 |wo            | span {'a'-'z'}      | *
  8 |   7 |              | return              | *
  4 |   7 |              | pcommit -> 2        | *
  2 |   7 |              | str " "             | *
  5 |   7 |              | fail -> 5           |
  5 |   7 |              | return              |
  5 |   7 |              | done                |
```

The exact meaning of the IR instructions is not discussed here.


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


### A complete Json parser

The following PEG defines a complete parser for the Json language - it will not produce
any captures, but simple traverse and validate the document:

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

  DOC            <- Json * !1
  Json           <- ?S * ( Number | Object | Array | String | True | False | Null ) * ?S
  Object         <- '{' * ( String * ":" * Json * *( "," * String * ":" * Json ) | ?S ) * "}"
  Array          <- "[" * ( Json * *( "," * Json ) | ?S ) * "]"

let doc = """ {"jsonrpc": "2.0", "method": "subtract", "params": [42, 23], "id": 1} """
doAssert match(doc).ok
```


### Captures

The following example shows captures in action. This PEG parses a HTTP
request into a nested Json tree:

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


The resulting Json data:
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

