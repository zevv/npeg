[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
![Stability: experimental](https://img.shields.io/badge/stability-stable-green.svg)

<img src="https://raw.githubusercontent.com/zevv/npeg/master/doc/npeg.png" alt="NPeg logo" align="left">

> "_Because friends don't let friends write parsers by hand_"

NPeg is a pure Nim pattern matching library. It provides macros to compile
patterns and grammars (PEGs) to Nim procedures which will parse a string and
collect selected parts of the input. PEGs are not unlike regular expressions,
but offer more power and flexibility, and have less ambiguities. (More about 
PEGs on [Wikipedia](https://en.wikipedia.org/wiki/Parsing_expression_grammar))

![Graph](/doc/syntax-diagram.png)

Some use cases where NPeg is useful are configuration or data file parsers,
robust protocol implementations, input validation, lexing of programming
languages or domain specific languages.

Some NPeg highlights:

- Grammar definitions and Nim code can be freely mixed. Nim code is embedded
  using the normal Nim code block syntax, and does not disrupt the grammar
  definition.

- NPeg-generated parsers can be used both at run and at compile time.

- NPeg offers various methods for tracing, optimizing and debugging
  your parsers.

- NPeg can parse sequences of any data types, also making it suitable as a
  stage-two parser for lexed tokens.

- NPeg can draw [cool diagrams](/doc/example-railroad.png)

## Contents

<!-- AutoContentStart -->
- [Quickstart](#quickstart)
- [Usage](#usage)
    * [Simple patterns](#simple-patterns)
    * [Grammars](#grammars)
- [Syntax](#syntax)
    * [Atoms](#atoms)
    * [Operators](#operators)
- [Precedence operators](#precedence-operators)
- [Captures](#captures)
    * [String captures](#string-captures)
    * [Code block captures](#code-block-captures)
        - [Custom match validations](#custom-match-validations)
        - [Passing state](#passing-state)
    * [Backreferences](#backreferences)
- [More about grammars](#more-about-grammars)
    * [Ordering of rules in a grammar](#ordering-of-rules-in-a-grammar)
    * [Templates, or parameterized rules](#templates-or-parameterized-rules)
    * [Composing grammars with libraries](#composing-grammars-with-libraries)
    * [Library rule overriding/shadowing](#library-rule-overridingshadowing)
- [Error handling](#error-handling)
    * [MatchResult](#matchresult)
    * [NpegParseError exceptions](#npegparseerror-exceptions)
    * [Other exceptions](#other-exceptions)
    * [Parser stack trace](#parser-stack-trace)
- [Advanced topics](#advanced-topics)
    * [Parsing other types then strings](#parsing-other-types-then-strings)
- [Some notes on using PEGs](#some-notes-on-using-pegs)
    * [Anchoring and searching](#anchoring-and-searching)
    * [Complexity and performance](#complexity-and-performance)
    * [End of string](#end-of-string)
    * [Non-consuming atoms and captures](#non-consuming-atoms-and-captures)
    * [Left recursion](#left-recursion)
    * [UTF-8 / Unicode](#utf-8--unicode)
- [Tracing and debugging](#tracing-and-debugging)
    * [Syntax diagrams](#syntax-diagrams)
    * [Grammar graphs](#grammar-graphs)
    * [Tracing](#tracing)
- [Compile-time configuration](#compile-time-configuration)
- [Tracing and debugging](#tracing-and-debugging-1)
- [Random stuff and frequently asked questions](#random-stuff-and-frequently-asked-questions)
    * [Why does NPeg not support regular PEG syntax?](#why-does-npeg-not-support-regular-peg-syntax)
    * [Can NPeg be used to parse EBNF grammars?](#can-npeg-be-used-to-parse-ebnf-grammars)
    * [NPeg and generic functions](#npeg-and-generic-functions)
- [Examples](#examples)
    * [Parsing arithmetic expressions](#parsing-arithmetic-expressions)
    * [A complete JSON parser](#a-complete-json-parser)
    * [Captures](#captures-1)
    * [More examples](#more-examples)
- [Future directions / Todos / Roadmap / The long run](#future-directions--todos--roadmap--the-long-run)

<!-- AutoContentEnd -->

## Quickstart

Here is a simple example showing the power of NPeg: The macro `peg` compiles a
grammar definition into a `parser` object, which is used to match a string and
place the key-value pairs into the Nim table `words`:

```nim
import npeg, strutils, tables

type Dict = Table[string, int]

let parser = peg("pairs", d: Dict):
  pairs <- pair * *(',' * pair) * !1
  word <- +Alpha
  number <- +Digit
  pair <- >word * '=' * >number:
    d[$1] = parseInt($2)

var words: Dict
doAssert parser.match("one=1,two=2,three=3,four=4", words).ok
echo words
```

Output:

```nim
{"two": 2, "three": 3, "one": 1, "four": 4}
```

A brief explanation of the above code:

* The macro `peg` is used to create a parser object, which uses `pairs` as the
  initial grammar rule to match. The variable `d` of type `Dict` will be available
  inside the code block parser for storing the parsed data.

* The rule `pairs` matches one `pair`, followed by zero or more times (`*`) a
  comma followed by a `pair`.

* The rules `word` and `number` match a sequence of one or more (`+`)
  alphabetic characters or digits, respectively. The `Alpha` and `Digit` rules
  are pre-defined rules matching the character classes `{'A'..'Z','a'..'z'}` 
  and `{'0'..'9'}`.

* The rule `pair` matches a `word`, followed by an equals sign (`=`), followed
  by a `number`.

* The `word` and `number` in the `pair` rule are captured with the `>`
  operator. The Nim code fragment below this rule is executed for every match,
  and stores the captured word and number in the `words` Nim table.


## Usage

The `patt()` and `peg()` macros can be used to compile parser functions:

- `patt()` creates a parser from a single anonymous pattern.

- `peg()` allows the definition of a set of (potentially recursive) rules 
          making up a complete grammar.

The result of these macros is an object of the type `Parser` which can be used
to parse a subject:

```nim
proc match(p: Parser, s: string) = MatchResult
proc matchFile(p: Parser, fname: string) = MatchResult
```

The above `match` functions returns an object of the type `MatchResult`:

```nim
MatchResult = object
  ok: bool
  matchLen: int
  matchMax: int
  ...
```

* `ok`: A boolean indicating if the matching succeeded without error. Note that
  a successful match does not imply that *all of the subject* was matched,
  unless the pattern explicitly matches the end-of-string.

* `matchLen`: The number of input bytes of the subject that successfully
  matched.

* `matchMax`: The highest index into the subject that was reached during
  parsing, *even if matching was backtracked or did not succeed*. This offset
  is usually a good indication of the location where the matching error
  occurred.

The string captures made during the parsing can be accessed with:

```nim
proc captures(m: MatchResult): seq[string]
```


### Simple patterns

A simple pattern can be compiled with the `patt` macro.

For example, the pattern below splits a string by white space:

```nim
let parser = patt *(*' ' * > +(1-' '))
echo parser.match("   one two three ").captures
```

Output:

```
@["one", "two", "three"]
```

The `patt` macro can take an optional code block which is used as code block
capture for the pattern:

```nim
var key, val: string
let p = patt >+Digit * "=" * >+Alpha:
  (key, val) = ($1, $2)

assert p.match("15=fifteen").ok
echo key, " = ", val
```

### Grammars

The `peg` macro provides a method to define (recursive) grammars. The first
argument is the name of initial patterns, followed by a list of named patterns.
Patterns can now refer to other patterns by name, allowing for recursion:

```nim
let parser = peg "ident":
  lower <- {'a'..'z'}
  ident <- *lower
doAssert parser.match("lowercaseword").ok
```

The order in which the grammar patterns are defined affects the generated
parser.
Although NPeg could always reorder, this is a design choice to give the user
more control over the generated parser:

* when a pattern `P1` refers to pattern `P2` which is defined *before* `P1`,
  `P2` will be inlined in `P1`.  This increases the generated code size, but
  generally improves performance.

* when a pattern `P1` refers to pattern `P2` which is defined *after* `P1`,
  `P2` will be generated as a subroutine which gets called from `P1`. This will
  reduce code size, but might also result in a slower parser.


## Syntax

The NPeg syntax is similar to normal PEG notation, but some changes were made
to allow the grammar to be properly parsed by the Nim compiler:

- NPeg uses prefixes instead of suffixes for `*`, `+`, `-` and `?`.
- Ordered choice uses `|` instead of `/` because of operator precedence.
- The explicit `*` infix operator is used for sequences.

NPeg patterns and grammars can be composed from the following parts:

```nim

Atoms:

   0              # matches always and consumes nothing
   1              # matches any character
   n              # matches exactly n characters
  'x'             # matches literal character 'x'
  "xyz"           # matches literal string "xyz"
 i"xyz"           # matches literal string, case insensitive
  {'x'..'y'}      # matches any character in the range from 'x'..'y'
  {'x','y','z'}   # matches any character from the set

Operators:

   P1 * P2        # concatenation
   P1 | P2        # ordered choice
   P1 - P2        # matches P1 if P2 does not match
  (P)             # grouping
  !P              # matches everything but P
  &P              # matches P without consuming input
  ?P              # matches P zero or one times
  *P              # matches P zero or more times
  +P              # matches P one or more times
  @P              # search for P
   P[n]           # matches P n times
   P[m..n]        # matches P m to n times

Precedence operators:

  P ^ N           # P is left associative with precedence N
  P ^^ N          # P is right associative with precedence N

String captures:  

  >P              # Captures the string matching  P 

Back references:

  R("tag", P)     # Create a named reference for pattern P
  R("tag")        # Matches the given named reference

Error handling:

  E"msg"          # Raise an `NPegParseError` exception
```

In addition to the above, NPeg provides the following built-in shortcuts for
common atoms, corresponding to POSIX character classes:

```nim
  Alnum  <- {'A'..'Z','a'..'z','0'..'9'}, # Alphanumeric characters
  Alpha  <- {'A'..'Z','a'..'z'},          # Alphabetic characters
  Blank  <- {' ','\t'},                   # Space and tab
  Cntrl  <- {'\x00'..'\x1f','\x7f'},      # Control characters
  Digit  <- {'0'..'9'},                   # Digits
  Graph  <- {'\x21'..'\x7e'},             # Visible characters
  Lower  <- {'a'..'z'},                   # Lowercase characters
  Print  <- {'\x21'..'\x7e',' '},         # Visible characters and spaces
  Space  <- {'\9'..'\13',' '},            # Whitespace characters
  Upper  <- {'A'..'Z'},                   # Uppercase characters
  Xdigit <- {'A'..'F','a'..'f','0'..'9'}, # Hexadecimal digits
```


### Atoms

Atoms are the basic building blocks for a grammar, describing the parts of the
subject that should be matched.

- Integer literal: `0` / `1` / `n`

  The int literal atom `n` matches exactly n number of bytes. `0` always
  matches, but does not consume any data.


- Character and string literals: `'x'` / `"xyz"` / `i"xyz"`

  Characters and strings are literally matched. If a string is prefixed with
  `i`, it will be matched case insensitive.


- Character sets: `{'x','y'}`

  Characters set notation is similar to native Nim. A set consists of zero or
  more comma separated characters or character ranges.

  ```nim
   {'x'..'y'}    # matches any character in the range from 'x'..'y'
   {'x','y','z'} # matches any character from the set 'x', 'y', and 'z'
  ```

  The set syntax `{}` is flexible and can take multiple ranges and characters
  in one expression, for example `{'0'..'9','a'..'f','A'..'F'}`.


### Operators

NPeg provides various prefix and infix operators. These operators combine or
transform one or more patterns into expressions, building larger patterns.

- Concatenation: `P1 * P2`

  ```
  o──[P1]───[P2]──o
  ```

  The pattern `P1 * P2` returns a new pattern that matches only if first `P1`
  matches, followed by `P2`.

  For example, `"foo" * "bar"` would only match the string `"foobar"`.

  Note: As an alternative for the `*` asterisk, the unicode glyph `∙` ("bullet
  operator", 0x2219) can also be used for concatenation.


- Ordered choice: `P1 | P2`

  ```
  o─┬─[P1]─┬─o
    ╰─[P2]─╯
  ```

  The pattern `P1 | P2` tries to first match pattern `P1`. If this succeeds,
  matching will proceed without trying `P2`. Only if `P1` can not be matched,
  NPeg will backtrack and try to match `P2` instead. Once either `P1` or `P2` has
  matched, the choice will be final ("commited"), and no more backtracking will
  be possible for this choice.

  For example `("foo" | "bar") * "fizz"` would match both `"foofizz"` and
  `"barfizz"`.

  NPeg optimizes the `|` operator for characters and character sets: The
  pattern `'a' | 'b' | 'c'` will be rewritten to a character set
  `{'a','b','c'}`.


- Difference: `P1 - P2`

  The pattern `P1 - P2` matches `P1` *only* if `P2` does not match. This is
  equivalent to `!P2 * P1`:
  
  ```
     ━━━━
  o──[P2]─»─[P1]──o
  ```

  NPeg optimizes the `-` operator for characters and character sets: The
  pattern `{'a','b','c'} - 'b'` will be rewritten to the character set
  `{'a','c'}`.


- Grouping: `(P)`

  Brackets are used to group patterns similar to normal arithmetic expressions.


- Not-predicate: `!P`

  ```
     ━━━
  o──[P]──o
  ```

  The pattern `!P` returns a pattern that matches only if the input does not
  match `P`.
  In contrast to most other patterns, this pattern does not consume any input.

  A common usage for this operator is the pattern `!1`, meaning "only succeed
  if there is not a single character left to match" - which is only true for
  the end of the string.


- And-predicate: `&P`

  ```
     ━━━
     ━━━
  o──[P]──o
  ```

  The pattern `&P` matches only if the input matches `P`, but will *not*
  consume any input. This is equivalent to `!!P`. This is denoted by a double
  negation in the railroad diagram, which is not very pretty unfortunately.

- Optional: `?P`

  ```
    ╭──»──╮
  o─┴─[P]─┴─o
  ```

  The pattern `?P` matches if `P` can be matched zero or more times, so
  essentially succeeds if `P` either matches or not.

  For example, `?"foo" * bar"` matches both `"foobar"` and `"bar"`.


- Match zero or more times: `*P`

  ```
    ╭───»───╮
  o─┴┬─[P]─┬┴─o
     ╰──«──╯
  ```

  The pattern `*P` tries to match as many occurrences of pattern `P` as
  possible - this operator always behaves *greedily*.

  For example, `*"foo" * "bar"` matches `"bar"`, `"fooboar"`, `"foofoobar"`,
  etc.


- Match one or more times: `+P`

  ```
  o─┬─[P]─┬─o
    ╰──«──╯
  ```

  The pattern `+P` matches `P` at least once, but also more times.
  It is equivalent to the `P * *P` - this operator always behave *greedily*.


- Search: `@P`

  This operator searches for pattern `P` using an optimized implementation. It
  is equivalent to `s <- *(1 - P) * P`, which can be read as "try to match as
  many characters as possible not matching `P`, and then match `P`:

  ```
    ╭─────»─────╮
    │  ━━━      │
  o─┴┬─[P]─»─1─┬┴»─[P]──o
     ╰────«────╯
  ```

  Note that this operator does not allow capturing the skipped data up to the
  match; if this is required you can manually construct a grammar to do this.


- Match exactly `n` times: `P[n]`

  The pattern `P[n]` matches `P` exactly `n` times.

  For example, `"foo"[3]` only matches the string `"foofoofoo"`:

  ```
  o──[P]─»─[P]─»─[P]──o
  ```


- Match `m` to `n` times: `P[m..n]`

  The pattern `P[m..n]` matches `P` at least `m` and at most `n` times.

  For example, `"foo[1,3]"` matches `"foo"`, `"foofoo"` and `"foofoofo"`:

  ```
          ╭──»──╮ ╭──»──╮
  o──[P]─»┴─[P]─┴»┴─[P]─┴─o
  ```


## Precedence operators

Note: This is an experimental feature, the implementation or API might change
in the future.

Precedence operators allows for the construction of "precedence climbing" or
"Pratt parsers" with NPeg. The main use for this feature is building parsers
for programming languages that follow the usual precedence and associativity
rules of arithmetic expressions.

- Left associative precedence of `N`: `P ^ N`

```
   <1<   
o──[P]──o
```

- Right associative precedence of `N`: `P ^^ N`

```
   >1> 
o──[P]──o
```

During parsing NPeg keeps track of the current precedence level of the parsed
expression - the default is `0` if no precedence has been assigned yet. When
the `^` operator is matched, either one of the next three cases applies:

- `P ^ N` where `N > 0` and `N` is lower then the current precedence: in this
  case the current precedence is set to `N` and parsing of pattern `P`
  continues.

- `P ^ N` where `N > 0` and `N` is higher or equal then the current precedence:
  parsing will fail and backtrack.

- `P ^ 0`: resets the current precedence to 0 and continues parsing. This main
  use case for this is parsing sub-expressions in parentheses.

The heart of a Pratt parser in NPeg would look something like this:

```nim
exp <- prefix * *infix

parenExp <- ( "(" * exp * ")" ) ^ 0

prefix <- number | parenExp

infix <- {'+','-'}    * exp ^  1 |
         {'*','/'}    * exp ^  2 |
         {'^'}        * exp ^^ 3:
```

More extensive documentation will be added later, for now take a look at the
example in `tests/precedence.nim`.


## Captures

```
     ╭╶╶╶╶╶╮
s o────[P]────o
     ╰╶╶╶╶╶╯
```

NPeg supports a number of ways to capture data when parsing a string.
The various capture methods are described here, including a concise example.

The capture examples below build on the following small PEG, which parses
a comma separated list of key-value pairs:

```nim
const data = "one=1,two=2,three=3,four=4"

let parser = peg "pairs":
  pairs <- pair * *(',' * pair) * !1
  word <- +Alpha
  number <- +Digit
  pair <- word * '=' * number

let r = parser.match(data)
```

### String captures

The basic method for capturing is marking parts of the peg with the capture
prefix `>`. During parsing NPeg keeps track of all matches, properly discarding
any matches which were invalidated by backtracking. Only when parsing has fully
succeeded it creates a `seq[string]` of all matched parts, which is then
returned in the `MatchData.captures` field.

In the example, the `>` capture prefix is added to the `word` and `number`
rules, causing the matched words and numbers to be appended to the result
capture `seq[string]`:

```nim
let parser = peg "pairs":
  pairs <- pair * *(',' * pair) * !1
  word <- +Alpha
  number <- +Digit
  pair <- >word * '=' * >number

let r = parser.match(data)
```

The resulting list of captures is now:

```nim
@["one", "1", "two", "2", "three", "3", "four", "4"]
```


### Code block captures

Code block captures offer the most flexibility for accessing matched data in
NPeg. This allows you to define a grammar with embedded Nim code for handling
the data during parsing.

Note that for code block captures, the Nim code gets executed during parsing,
*even if the match is part of a pattern that fails and is later backtracked*.

When a grammar rule ends with a colon `:`, the next indented block in the
grammar is interpreted as Nim code, which gets executed when the rule has been
matched. Any string captures that were made inside the rule are available to
the Nim code in the injected variable `capture[]` of type `seq[Capture]`:

```
type Capture = object
  s*: string      # The captured string
  si*: int        # The index of the captured string in the subject
```

The total subject matched by the code block rule is available in `capture[0]`
Any additional explicit `>` string captures made by the rule or any of its
child rules will be available as `capture[1]`, `capture[2]`, ...

For convenience there is syntactic sugar available in the code block capture
blocks:

- The variables `$0` to `$9` are rewritten to `capture[n].s` and can be used to
  access the captured strings. The `$` operator uses then usual Nim precedence,
  thus these variables might need parentheses or different ordering in some
  cases, for example `$1.parseInt` should be written as `parseInt($1)`.

- The variables `@0` to `@9` are rewritten to `capture[n].si` and can be used
  to access the offset in the subject of the matched captures.

Example:
```nim
let p = peg foo:
  foo <- >(1 * >1) * 1:
    echo "$0 = ", $0
    echo "$1 = ", $1
    echo "$2 = ", $2
       
echo p.match("abc").ok
```

Will output

```nim
$0 = abc
$1 = ab
$2 = b
```

Code block captures consume all embedded string captures, so these captures
will no longer be available after matching.

A code block capture can also produce captures by calling the `push(s: string)`
function from the code block. Note that this is an experimental feature and
that the API might change in future versions.

The example has been extended to capture each word and number with the `>`
string capture prefix. When the `pair` rule is matched, the attached code block
is executed, which adds the parsed key and value to the `words` table.

```nim
from strutils import parseInt
var words = initTable[string, int]()

let parser = peg "pairs":
  pairs <- pair * *(',' * pair) * !1
  word <- +Alpha
  number <- +Digit
  pair <- >word * '=' * >number:
    words[$1] = parseInt($2)

let r = parser.match(data)
```

After the parsing finished, the `words` table will now contain:

```nim
{"two": 2, "three": 3, "one": 1, "four": 4}
```


#### Custom match validations

Code block captures can be used for additional validation of a captured string:
the code block can call the functions `fail()` or `validate(bool)` to indicate
if the match should succeed or fail. Failing matches are handled as if the
capture itself failed and will result in the usual backtracking. When the
`fail()` or `validate()` functions are not called, the match will succeed
implicitly.

For example, the following rule will check if a passed number is a valid
`uint8` number:

```nim
uint8 <- >Digit[1..3]:
  let v = parseInt($a)
  validate v>=0 and v<=255
```

The following grammar will cause the whole parse to fail when the `error` rule
matches:

```nim
error <- 0:
  fail()
```

Note: The Nim code block is running within the NPeg parser context and in
theory could access to its internal state - this could be used to create custom
validator/matcher functions that can inspect the subject string, do lookahead
or lookback, and adjust the subject index to consume input. At the time of
writing, NPeg lacks a formal API or interface for this though, and I am not
sure yet what this should look like - If you are interested in doing this,
contact me so we can discuss the details.

#### Passing state

NPeg allows passing of data of a specific type to the `match()` function, this
value is then available inside code blocks as a variable. This mitigates the
need for global variables for storing or retrieving data in access captures.

The syntax for passing data in a grammar is:

```
peg(name, identifier: Type)
```

For example, the above parser can be rewritten as such:

```nim
type Dict = Table[string, int]

let parser = peg("pairs", userdata: Dict):
  pairs <- pair * *(',' * pair) * !1
  word <- +Alpha
  number <- +Digit
  pair <- >word * '=' * >number:
    userdata[$1] = parseInt($2)

var words: Dict
let r = parser.match(data, words)
```


### Backreferences

Backreferences allow NPeg to match an exact string that matched earlier in the
grammar. This can be useful to match repetitions of the same word, or for
example to match so called here-documents in programming languages.

For this, NPeg offers the `R` operator with the following two uses:

* The `R(name, P)` pattern creates a named reference for pattern `P` which can
  be referred to by name in other places in the grammar.

* The pattern `R(name)` matches the contents of the named reference that
  earlier been stored with `R(name, P)` pattern.

For example, the following rule will match only a string which will have the 
same character in the first and last position:

```
patt R("c", 1) * *(1 - R("c")) * R("c") * !1
```

The first part of the rule `R("c", 1)` will match any character, and store this
in the named reference `c`. The second part will match a sequence of zero or
more characters that do not match reference `c`, followed by reference `c`.


## More about grammars


### Ordering of rules in a grammar

Repetitive inlining of rules might cause a grammar to grow too large, resulting
in a huge executable size and slow compilation. NPeg tries to mitigate this in
two ways:

* Patterns that are too large will not be inlined, even if the above ordering
  rules apply.

* NPeg checks the size of the total grammar, and if it thinks it is too large
  it will fail compilation with the error message `NPeg: grammar too complex`.

Check the section "Compile-time configuration" below for more details about too
complex grammars.

The parser size and performance depends on many factors; when performance
and/or code size matters, it pays to experiment with different orderings and
measure the results.

When in doubt, check the generated parser instructions by compiling with the
`-d:npegTrace` or `-d:npegDotDir` flags - see the section Tracing and
Debugging for more information.

At this time the upper limit is 4096 rules, this might become a configurable
number in a future release.

For example, the following grammar will not compile because recursive inlining
will cause it to expand to a parser with more then 4^6 = 4096 rules:

```
let p = peg "z":
  f <- 1
  e <- f * f * f * f
  d <- e * e * e * e
  c <- d * d * d * d
  b <- c * c * c * c
  a <- b * b * b * b
  z <- a * a * a * a
```

The fix is to change the order of the rules so that instead of inlining NPeg
will use a calling mechanism:

```
let p = peg "z":
  z <- a * a * a * a
  a <- b * b * b * b
  b <- c * c * c * c
  c <- d * d * d * d
  d <- e * e * e * e
  e <- f * f * f * f
  f <- 1
```

When in doubt check the generated parser instructions by compiling with the
`-d:npegTrace` flag - see the section Tracing and Debugging for more
information.


### Templates, or parameterized rules

When building more complex grammars you may find yourself duplicating certain
constructs in patterns over and over again. To avoid code repetition (DRY),
NPeg provides a simple mechanism to allow the creation of parameterized rules.
In good Nim-fashion these rules are called "templates". Templates are defined
just like normal rules, but have a list of arguments, which are referred to in
the rule. Technically, templates just perform a basic search-and-replace
operation: every occurrence of a named argument is replaced by the exact
pattern passed to the template when called.

For example, consider the following grammar:

```nim
numberList <- +Digit * *( ',' * +Digit)
wordList <- +Alpha * *( ',' * +Alpha)
```

This snippet uses a common pattern twice for matching lists: `p * *( ',' * p)`.
This matches pattern `p`, followed by zero or more occurrences of a comma
followed by pattern `p`. For example, `numberList` will match the string
`1,22,3`.

The above example can be parameterized with a template like this:

```nim
commaList(item) <- item * *( ',' * item )
numberList <- commaList(+Digit)
wordList <- commaList(+Alpha)
```

Here the template `commaList` is defined, and any occurrence of its argument
'item' will be replaced with the patterns passed when calling the template.
This template is used to define the more complex patterns `numberList` and
`wordList`.

Templates may invoke other templates recursively; for example the above can
even be further generalized:

```nim
list(item, sep) <- item * *( sep * item )
commaList(item) <- list(item, ',')
numberList <- commaList(+Digit)
wordList <- commaList(+Alpha)
```


### Composing grammars with libraries

For simple grammars it is usually fine to build all patterns from scratch from
atoms and operators, but for more complex grammars it makes sense to define
reusable patterns as basic building blocks.

For this, NPeg keeps track of a global library of patterns and templates. The
`grammar` macro can be used to add rules or templates to this library. All
patterns in the library will be stored with a *qualified* identifier in the
form `libraryname.patternname`, by which they can be referred to at a later
time.

For example, the following fragment defines three rules in the library with the
name `number`. The rules will be stored in the global library and are referred
to in the peg by their qualified names `number.dec`, `number.hex` and
`number.oct`:

```nim
grammar "number":
  dec <- {'1'..'9'} * *{'0'..'9'}
  hex <- i"0x" * +{'0'..'9','a'..'f','A'..'F'}
  oct <- '0' * *{'0'..'9'}

let p = peg "line":
  line <- int * *("," * int)
  int <- number.dec | number.hex | number.oct

let r = p.match("123,0x42,0644")
```

NPeg offers a number of pre-defined libraries for your convenience, these can
be found in the `npeg/lib` directory. A library an be imported with the regular
Nim `import` statement, all rules defined in the imported file will then be
added to NPeg's global pattern library. For example:

```nim
import npeg/lib/uri
```


Note that templates defined in libraries do not implicitly bind the the rules
from that grammar; instead, you need to explicitly qualify the rules used in
the template to refer to the grammar. For example:

```nim
grammar "foo":
  open <- "("
  close <- ")"
  inBrackets(body): foo.open * body * foo.close
```

### Library rule overriding/shadowing

To allow the user to add custom captures to imported grammars or rules, it is
possible to *override* or *shadow* an existing rule in a grammar.

Overriding will replace the rule from the library with the provided new rule,
allowing the caller to change parts of an imported grammar. A overridden rule
is allowed to reference the original rule by name, which will cause the new
rule to *shadow* the original rule. This will effectively rename the original
rule and replace it with the newly defined rule which will call the original
referred rule.

For example, the following snippet will reuse the grammar from the `uri`
library and capture some parts of the URI in a Nim object:

```nim
import npeg/lib/uri

type Uri = object
  host: string
  scheme: string
  path: string
  port: int

var myUri: Uri

let parser = peg "line":
  line <- uri.URI
  uri.scheme <- >uri.scheme: myUri.scheme = $1
  uri.host <- >uri.host:     myUri.host = $1
  uri.port <- >uri.port:     myUri.port = parseInt($1)
  uri.path <- >uri.path:     myUri.path = $1

echo parser.match("http://nim-lang.org:8080/one/two/three")
echo myUri  # --> (host: "nim-lang.org", scheme: "http", path: "/one/two/three", port: 8080)
```

## Error handling

NPeg offers a number of ways to handle errors during parsing a subject string;
what method best suits your parser depends on your requirements. 


### MatchResult

The most simple way to handle errors is to inspect the `MatchResult` object
that is returned by the `match()` proc:

```nim
MatchResult = object
  ok: bool
  matchLen: int
  matchMax: int
```

The `ok` field in the `MatchResult` indicates if the parser was successful:
when the complete pattern has been matched this value will be set to `true`,
if the complete pattern did not match the subject the value will be `false`.

In addition to the `ok` field, the `matchMax` field indicates the maximum
offset into the subject the parser was able to match the string. If the
matching succeeded `matchMax` equals the total length of the subject, if the
matching failed, the value of `matchMax` is usually a good indication of where
in the subject string the error occurred:

```
let a = patt 4
let r = a.match("123")
if not r.ok:
  echo "Parsing failed at position ", r.matchMax
```

### NpegParseError exceptions

When, during matching, the parser reaches an `E"message"` atom in the grammar,
NPeg will raise an `NPegParseError` exception with the given message.
The typical use case for this atom is to be combine with the ordered choice `|`
operator to generate helpful error messages.
The following example illustrates this:

```nim
let parser = peg "list":
  list <- word * *(comma * word) * !1
  word <- +Alpha | E"expected word"
  comma <- ',' | E"expected comma"

try:
  echo parser.match("one,two;three")
except NPegParseError as e:
  echo "Parsing failed at position ", e.matchMax, ": ", e.msg
```

The rule `comma` tries to match the literal `','`. If this can not be matched,
the rule `E"expected comma"` will match instead, where `E` will raise an
`NPegParseError` exception.

The `NPegParseError` type contains the same two fields as `MatchResult` to
indicate where in the subject string the match failed: `matchLen` and
`matchMax`, which can be used as an indication of the location of the parse
error:

```
Parsing failed at position 7: expected comma
```


### Other exceptions

NPeg can raise a number of other exception types during parsing:

- `NPegParseError`: described in the previous section

- `NPegStackOverflowError`: a stack overflow occured in the backtrace
  or call stack; this is usually an indication of a faulty or too complex
  grammar.

- `NPegUnknownBackrefError`: An unknown back reference identifier is used in an 
  `R()` rule.

- `NPegCaptureOutOfRangeError`: A code block capture tries to access a capture
  that is not available using the `$` notation or by accessing the `capture[]`
  seq.


All the above errors are inherited from the generic `NPegException` object.


### Parser stack trace

If an exception is raised from within an NPeg parser - either by the `E` atom
or by nim code in a code block capture - NPeg will augment the Nim stack trace
with frames indicating where in the grammar the exception occured.

The above example will generate the following stack trace, note the last two
entries which are added by NPeg and show the rules in which the exception
occured:

```
/tmp/list.nim(9)         list
./npeg/src/npeg.nim(142) match
./npeg/src/npeg.nim(135) match
/tmp/flop.nim(4)         list <- word * *(comma * word) * eof
/tmp/flop.nim(7)         word <- +{'a' .. 'z'} | E"expected word"
Error: unhandled exception: Parsing error at #14: "expected word" [NPegParseError]
```

Note: this requires Nim 'devel' or version > 1.6.x; on older versions you can
use `-d:npegStackTrace` to make NPeg dump the stack to stdout.


## Advanced topics

### Parsing other types then strings

Note: This is an experimental feature, the implementation or API might change
in the future.

NPeg was originally designed to parse strings like a regular PEG engine, but
has since evolved into a generic parser that can parse any subject of type
`openArray[T]`. This section describes how to use this feature.

- The `peg()` macro must be passed an additional argument specifying the base
  type `T` of the subject; the generated parser will then parse a subject of
  type `openArray[T]`. When not given, the default type is `char`, and the parser
  parsers `openArray[char]`, or more typically, `string`.

- When matching non-strings, some of the usual atoms like strings or character
  sets do not make sense in a grammar, instead the grammar uses literal atoms.
  Literals can be specified in square brackets and are interpreted as any Nim
  code: `[foo]`, `[1+1]` or `["foo"]` are all valid literals.

- When matching non-strings, captures will be limited to only a single element
  of the base type, as this makes more sense when parsing a token stream.

For an example of this feature check the example in `tests/lexparse.nim` - this
implements a classic parser with separate lexing and parsing stages.


## Some notes on using PEGs


### Anchoring and searching

Unlike regular expressions, PEGs are always matched in *anchored* mode only:
the defined pattern is matched from the start of the subject string.
For example, the pattern `"bar"` does not match the string `"foobar"`.

To search for a pattern in a stream, a construct like this can be used:

```nim
p <- "bar"
search <- p | 1 * search
```

The above grammar first tries to match pattern `p`, or if that fails, matches
any character `1` and recurs back to itself. Because searching is a common
operation, NPeg provides the builtin `@P` operator for this.


### Complexity and performance

Although it is possible to write patterns with exponential time complexity for
NPeg, they are much less common than in regular expressions, thanks to the
limited backtracking. In particular, patterns written without grammatical rules
always have a worst-case time `O(n^k)` (and space `O(k)`, which is constant for
a given pattern), where `k` is the pattern's star height. Moreover, NPeg has a
simple and clear performance model that allows programmers to understand and
predict the time complexity of their patterns. The model also provides a firm
basis for pattern optimizations.

(Adapted from Ierusalimschy, "A Text Pattern-Matching Tool based on Parsing
Expression Grammars", 2008)


### End of string

PEGs do not care what is in the subject string after the matching succeeds. For
example, the rule `"foo"` happily matches the string `"foobar"`. To make sure
the pattern matches the end of string, this has to be made explicit in the
pattern.

The idiomatic notation for this is `!1`, meaning "only succeed if there is not
a single character left to match" - which is only true for the end of the
string.


### Non-consuming atoms and captures

The lookahead(`&`) and not(`!`) operators may not consume any input, and make
sure that after matching the internal parsing state of the parser is reset to
as is was before the operator was started, including the state of the captures.
This means that any captures made inside a `&` and `!` block also are
discarded. It is possible however to capture the contents of a non-consuming
block with a code block capture, as these are _always_ executed, even when the
parser state is rolled back afterwards.


### Left recursion

NPeg does not support left recursion (this applies to PEGs in general). For
example, the rule

```nim
A <- A | 'a'
```

will cause an infinite loop because it allows for left-recursion of the
non-terminal `A`.

Similarly, the grammar

```nim
A <- B | 'a' A
B <- A
```

is problematic because it is mutually left-recursive through the non-terminal
`B`.

Note that loops of patterns that can match the empty string will not result in
the expected behavior. For example, the rule `*0` will cause the parser to
stall and go into an infinite loop.


### UTF-8 / Unicode

NPeg has no built-in support for Unicode or UTF-8, instead is simply able to
parse UTF-8 documents just as like any other string. NPeg comes with a simple
UTF-8 grammar library which should simplify common operations like matching a
single code point or character class. The following grammar splits an UTF-8
document into separate characters/glyphs by using the `utf8.any` rule:

```nim
import npeg/lib/utf8

let p = peg "line":
  line <- +char
  char <- >utf8.any

let r = p.match("γνωρίζω")
echo r.captures()   # --> @["γ", "ν", "ω", "ρ", "ί", "ζ", "ω"]
```


## Tracing and debugging

### Syntax diagrams

When compiled with `-d:npegGraph`, NPeg will dump 
[syntax diagrams](https://en.wikipedia.org/wiki/Syntax_diagram)
(also known as railroad diagrams) for all parsed rules.

Syntax diagrams are sometimes helpful to understand or debug a grammar, or to
get more insight in a grammars' complexity.

```
                              ╭─────────»──────────╮                     
                              │      ╭─────»──────╮│                     
                ╭╶╶╶╶╶╶╶╶╶╶╮  │      │  ━━━━      ││         ╭╶╶╶╶╶╶╶╮   
inf o──"INF:"─»───[number]───»┴─","─»┴┬─[lf]─»─1─┬┴┴»─[lf]─»───[url]────o
                ╰╶╶╶╶╶╶╶╶╶╶╯          ╰────«─────╯           ╰╶╶╶╶╶╶╶╯   
```

* Optionals (`?`) are indicated by a forward arrow overhead.
* Repeats ('+') are indicated by a backwards arrow underneath.
* Literals (strings, chars, sets) are printed in purple.
* Non-terminals are printed in cyan between square brackets.
* Not-predicates (`!`) are overlined in red. Note that the diagram does not
  make it clear that the input for not-predicates is not consumed.
* Captures are boxed in a gray rectangle, optionally including the capture
  name.

[Here](/doc/example-railroad.png) is a a larger example of an URL parser.

### Grammar graphs

NPeg can generate a graphical representation of a grammar to show the relations
between rules. The generated output is a `.dot` file which can be processed by
the Graphviz tool to generate an actual image file.

When compiled with `-d:npegDotDir=<PATH>`, NPeg will generate a `.dot` file for
each grammar in the code and write it to the given directory.

![graph](/doc/example-graph.png)

* Edge colors represent the rule relation:
  grey=inline, blue=call, green=builtin

* Rule colors represent the relative size/complexity of a rule:
  black=<10, orange=10..100, red=>100

Large rules result in larger generated code and slow compile times. Rule size
can generally be decreased by changing the rule order in a grammar to allow
NPeg to call rules instead of inlining them.


### Tracing

When compiled with `-d:npegTrace`, NPeg will dump its intermediate
representation of the compiled PEG, and will dump a trace of the execution
during matching. These traces can be used for debugging or optimization of a
grammar.

For example, the following program:

```nim
let parser = peg "line":
  space <- ' '
  line <- word * *(space * word)
  word <- +{'a'..'z'}

discard parser.match("one two")
```

will output the following intermediate representation at compile time. From
the IR it can be seen that the `space` rule has been inlined in the `line`
rule, but that the `word` rule has been emitted as a subroutine which gets
called from `line`:

```
line:
   0: line           opCall 6 word        word
   1: line           opChoice 5           *(space * word)
   2:  space         opStr " "            ' '
   3: line           opCall 6 word        word
   4: line           opPartCommit 2       *(space * word)
   5:                opReturn

word:
   6: word           opSet '{'a'..'z'}'   {'a' .. 'z'}
   7: word           opSpan '{'a'..'z'}'  +{'a' .. 'z'}
   8:                opReturn
```

At runtime, the following trace is generated. The trace consists of a number
of columns:

1. The current instruction pointer, which maps to the compile time dump.
2. The index into the subject.
3. The substring of the subject.
4. The name of the rule from which this instruction originated.
5. The instruction being executed.
6. The backtrace stack depth.

```
  0|  0|one two                 |line           |call -> word:6                          |
  6|  0|one two                 |word           |set {'a'..'z'}                          |
  7|  1|ne two                  |word           |span {'a'..'z'}                         |
  8|  3| two                    |               |return                                  |
  1|  3| two                    |line           |choice -> 5                             |
  2|  3| two                    | space         |chr " "                                 |*
  3|  4|two                     |line           |call -> word:6                          |*
  6|  4|two                     |word           |set {'a'..'z'}                          |*
  7|  5|wo                      |word           |span {'a'..'z'}                         |*
  8|  7|                        |               |return                                  |*
  4|  7|                        |line           |pcommit -> 2                            |*
  2|  7|                        | space         |chr " "                                 |*
   |  7|                        |               |fail                                    |*
  5|  7|                        |               |return (done)                           |
```

The exact meaning of the IR instructions is not discussed here.


## Compile-time configuration

NPeg has a number of configurable setting which can be configured at compile
time by passing flags to the compiler. The default values should be ok in most
cases, but if you ever run into one of those limits you are free to configure
those to your liking:

* `-d:npegPattMaxLen=N` This is the maximum allowed length of NPeg's internal
  representation of a parser, before it gets translated to Nim code. The reason
  to check for an upper limit is that some grammars can grow exponentially by
  inlining of patterns, resulting in slow compile times and oversized
  executable size. (default: 4096)

* `-d:npegInlineMaxLen=N` This is the maximum allowed length of a pattern to be
  inlined. Inlining generally results in a faster parser, but also increases
  code size. It is valid to set this value to 0; in that case NPeg will never
  inline patterns and use a calling mechanism instead, this will result in the
  smallest code size. (default: 50)

* `-d:npegRetStackSize=N` Maximum allowed depth of the return stack for the
  parser. The default value should be high enough for practical purposes, the
  stack depth is only limited to detect invalid grammars. (default: 1024)

* `-d:npegBackStackSize=N` Maximum allowed depth of the backtrace stack for the
  parser. The default value should be high enough for practical purposes, the
  stack depth is only limited to detect invalid grammars. (default: 1024)

* `-d:npegGcsafe` This is a workaround for the case where NPeg needs to be used
  from a `{.gcsafe.}` context when using threads. This will mark the generated
  matching function to be `{.gcsafe.}`.


## Tracing and debugging

NPeg has a number of compile time flags to enable tracing and debugging of the
generated parser:

* `-d:npegTrace`: Enable compile time and run time tracing. Please refer to the 
  section 'Tracing' for more details.

* `-d:npegGraph`: Dump syntax diagrams of all parsed rules at compile time.

These flags are meant for debugging NPeg itself, and are typically not useful
to the end user:

* `-d:npegDebug`: Enable more debug info. Meant for NPeg development debugging
  purposes only.

* `-d:npegExpand`: Dump the generated Nim code for all parsers defined in the
  program. Meant for NPeg development debugging purposes only.

* `-d:npegStacktrace`: When enabled, NPeg will dump a stack trace of the
  current position in the parser when an exception is thrown by NPeg itself or
  by Nim code in code block captures.


## Random stuff and frequently asked questions


### Why does NPeg not support regular PEG syntax?

The NPeg syntax is similar, but not exactly the same as the official PEG
syntax: it uses some different operators, and prefix instead of postfix
operators. The reason for this is that the NPeg grammar is parsed by a Nim
macro in order to allow code block captures to embed Nim code, which puts some
limitations on the available syntax. Also, NPeg's operators are chosen so that
they have the right precedence for PEGs.

The result is that the grammer itself is expressed as valid Nim, which has the
nice side effect of allowing syntax highlighting and code completion work with
your favorite editor.


### Can NPeg be used to parse EBNF grammars?

Almost, but not quite. Although PEGS and EBNF look quite similar, there are
some subtle but important differences which do not allow a literal translation
from EBNF to PEG. Notable differences are left recursion and ordered choice.
Also, see "From EBNF to PEG" from Roman R. Redziejowski.


### NPeg and generic functions

Nim's macro system is sometimes finicky and not well defined, and NPeg seems to
push it to the limit. This means that you might run into strange and
unexpected issues, especially when mixing NPeg with generic code.

If you run into weird error messages that do not seem to make sense when using
NPeg from generic procs, check the links below for more information and
possible workarounds:

- https://github.com/nim-lang/Nim/issues/22740
- https://github.com/zevv/npeg/issues/68


## Examples

### Parsing arithmetic expressions

```nim
let parser = peg "line":
  exp      <- term   * *( ('+'|'-') * term)
  term     <- factor * *( ('*'|'/') * factor)
  factor   <- +{'0'..'9'} | ('(' * exp * ')')
  line     <- exp * !1

doAssert parser.match("3*(4+15)+2").ok
```


### A complete JSON parser

The following PEG defines a complete parser for the JSON language - it will not
produce any captures, but simple traverse and validate the document:

```nim
let s = peg "doc":
  S              <- *Space
  jtrue          <- "true"
  jfalse         <- "false"
  jnull          <- "null"

  unicodeEscape  <- 'u' * Xdigit[4]
  escape         <- '\\' * ({ '{', '"', '|', '\\', 'b', 'f', 'n', 'r', 't' } | unicodeEscape)
  stringBody     <- ?escape * *( +( {'\x20'..'\xff'} - {'"'} - {'\\'}) * *escape)
  jstring         <- ?S * '"' * stringBody * '"' * ?S

  minus          <- '-'
  intPart        <- '0' | (Digit-'0') * *Digit
  fractPart      <- "." * +Digit
  expPart        <- ( 'e' | 'E' ) * ?( '+' | '-' ) * +Digit
  jnumber         <- ?minus * intPart * ?fractPart * ?expPart

  doc            <- JSON * !1
  JSON           <- ?S * ( jnumber | jobject | jarray | jstring | jtrue | jfalse | jnull ) * ?S
  jobject        <- '{' * ( jstring * ":" * JSON * *( "," * jstring * ":" * JSON ) | ?S ) * "}"
  jarray         <- "[" * ( JSON * *( "," * JSON ) | ?S ) * "]"

doAssert s.match(json).ok

let doc = """ {"jsonrpc": "2.0", "method": "subtract", "params": [42, 23], "id": 1} """
doAssert parser.match(doc).ok
```


### Captures

The following example shows how to use code block captures. The defined
grammar will parse a HTTP response document and extract structured data from
the document into a Nim object:

```nim
import npeg, strutils, tables

type
  Request = object
    proto: string
    version: string
    code: int
    message: string
    headers: Table[string, string]

# HTTP grammar (simplified)

let parser = peg("http", userdata: Request):
  space       <- ' '
  crlf        <- '\n' * ?'\r'
  url         <- +(Alpha | Digit | '/' | '_' | '.')
  eof         <- !1
  header_name <- +(Alpha | '-')
  header_val  <- +(1-{'\n'}-{'\r'})
  proto       <- >+Alpha:
    userdata.proto = $1
  version     <- >(+Digit * '.' * +Digit):
    userdata.version = $1
  code        <- >+Digit:
    userdata.code = parseInt($1)
  msg         <- >(+(1 - '\r' - '\n')):
    userdata.message = $1
  header      <- >header_name * ": " * >header_val:
    userdata.headers[$1] = $2
  response    <- proto * '/' * version * space * code * space * msg
  headers     <- *(header * crlf)
  http        <- response * crlf * headers * eof


# Parse the data and print the resulting table

const data = """
HTTP/1.1 301 Moved Permanently
Content-Length: 162
Content-Type: text/html
Location: https://nim.org/
"""

var request: Request
let res = parser.match(data, request)
echo request
```

The resulting data:

```nim
(
  proto: "HTTP",
  version: "1.1",
  code: 301,
  message: "Moved Permanently",
  headers: {
    "Content-Length": "162",
    "Content-Type":
    "text/html",
    "Location": "https://nim.org/"
  }
)
```


### More examples

More examples can be found in tests/examples.nim.


## Future directions / Todos / Roadmap / The long run

Here are some things I'd like to have implemented one day. Some are hard and
require me to better understand what I'm doing first. In no particular order:

- Handling left recursion: PEGs are typically not good at handling grammar
  invoking left recursion, see 
  https://en.wikipedia.org/wiki/Parsing_expression_grammar#Indirect_left_recursion
  for an explanation of the problem. However, some smart people have found a way
  to make this work anyway, but I am not yet able to understand this well enough
  to implement this in NPeg.
  https://github.com/zevv/npeg/blob/master/doc/papers/Left_recursion_in_parsing_expression_grammars.pdf

- Design and implement a proper API for code block captures. The current API
  feels fragile and fragmented (`capture[], $1/$2, fail(), validate()`), and
  does not offer solid primitives to make custom match functions yet, something
  better should be in place before NPeg goes v1.0.

- Resuming/streaming: The current parser is almost ready to be invoked multiple
  times, resuming parsing where it left off - this should allow parsing of
  (infinite) streams. The only problem not solved yet is how to handle
  captures: when a block of data is parsed it might contain data which must
  later be available to collect the capture. Not sure how to handle this yet.

- Memoization: I guess it would be possible to add (limited) memoization to 
  improve performance, but no clue where to start yet.

- Parallelization: I wonder if parsing can parallelized: when reaching an
  ordered choice, multiple threads should be able to try to parse each
  individual choice. I do see problems with captures here, though.

- I'm not happy about the `{.gcsafe.}` workaround. I'd be happy to hear any
  ideas on how to improve this.

