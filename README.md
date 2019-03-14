
# NPeg

NPeg is an early stage pure Nim pattern-matching library. It provides macros to compile
patterns and grammars to Nim procedures which will parse a string.

## Syntax

NPeg patterns can be composed from the following parts.


### Atoms

```nim
 'x'           # matches literal character 'x'
 "xyz"         # matches literal string "xyz"
i"xyz"         # matches literal string, case insensitive
 []            # matches any character
 ['x'..'y']    # matches any character in the range from 'x'..'y'
 ['x','y','z'] # matches any character from the set
```

The set syntax `[]` is flexible and can take multiple ranges and characters in
one expression, for example `['0'..'9','a'..'f','A'..'F']`. For ranges the
alternate syntax `['a'-'z']` can be used as well

### Operators

```nim
(P)            # grouping
-P             # matches everything but P
 P1 * P2       # concatenation
 P1 | P2       # ordered choice
 P1 - P2       # matches P1 if P2 does not match
?P             # matches P 0 or 1 times
*P             # matches P 0 or more times
+P             # matches P 1 or more times P
 P{n}          # matches P n times
 P{m..n}       # matches P m to n times
```

### Captures

Captures are still a work in progress.

```
C(P)           # Captures all text matched in P
Cp(proc, P)    # Passes the captured string to procedure `proc`
```


## NPeg vs PEG

The NPeg syntax is similar to normal PEG notation, but some changes were made
to allow the grammar to be properly parsed by the Nim compiler:

- NPeg uses prefixes instead of suffixes for `*`, `+`, `-` and `?`
- Ordered choice uses `|` instead of `/` because of the operator precedence
- The explict `*` infix operator is used for sequences


## Usage

### Simple patterns

A simple pattern can be compiled with the `patt` macro:

```nim
let p = patt *['a'..'z']
doAssert p("lowercaseword")
```

### Grammars

The `peg` macro provides a method to define (recursive) grammars. The first
argument is the name of initial patterns, followed by a list of named patterns.
Patterns can now refer to other patterns by name, allowing for recursion:

```nim
let p = peg "ident":
  lower <- ['a'..'z']
  ident <- *lower
doAssert p("lowercaseword")
```


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

Parsing mathematical expressions:

```nim
let s = peg "line":
  ws       <- *' '
  digit    <- ['0'..'9'] * ws
  number   <- +digit * ws
  termOp   <- ['+', '-'] * ws
  factorOp <- ['*', '/'] * ws
  open     <- '(' * ws
  close    <- ')' * ws
  eol      <- -[]
  exp      <- term * *(termOp * term)
  term     <- factor * *(factorOp * factor)
  factor   <- number | (open * exp * close)
  line     <- ws * exp * eol

doAssert s "3 * (4+5) + 2"
```


A complete JSON parser:

```nim

let match = peg "DOC":
  S              <- *[' ','\t','\r','\n']
  String         <- ?S * '"' * *(['\x20'..'\xff'] - '"' - '\\' | Escape ) * '"' * ?S
  Escape         <- '\\' * ([ '[', '"', '|', '\\', 'b', 'f', 'n', 'r', 't' ] | UnicodeEscape)
  UnicodeEscape  <- 'u' * ['0'..'9','A'..'F','a'..'f']{4}
  True           <- "true"
  False          <- "false"
  Null           <- "null"
  Number         <- ?Minus * IntPart * ?FractPart * ?ExpPart
  Minus          <- '-'
  IntPart        <- '0' | ['1'..'9'] * *['0'..'9']
  FractPart      <- "." * +['0'..'9']
  ExpPart        <- ( 'e' | 'E' ) * ?( '+' | '-' ) * +['0'..'9']
  DOC            <- JSON * -[]
  JSON           <- ?S * ( Number | Object | Array | String | True | False | Null ) * ?S
  Object         <- '{' * ( String * ":" * JSON * *( "," * String * ":" * JSON ) | ?S ) * "}"
  Array          <- "[" * ( JSON * *( "," * JSON ) | ?S ) * "]"

let doc = """ {"jsonrpc": "2.0", "method": "subtract", "params": [42, 23], "id": 1} """
doAssert match(doc)
```



