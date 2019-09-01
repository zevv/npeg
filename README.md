![NPeg](/doc/npeg.png)

NPeg is a pure Nim pattern matching library. It provides macros to compile
patterns and grammars (PEGs) to Nim procedures which will parse a string and
collect selected parts of the input. PEGs are not unlike regular expressions,
but offer more power and flexibility, and have less ambiguities. (More about 
PEGs on [wikipedia](https://en.wikipedia.org/wiki/Parsing_expression_grammar))

Some use cases where NPeg is useful are configuration or data file parsers,
robust protocol implementations, input validation, lexing of programming
languages or domain specific languages.

Some NPeg highlights:

- Grammar definitions and Nim code can be freely mixed. Nim code is embedded
  using the normal Nim code block syntax, and does not disrupt the grammar
  definition.

- NPeg-generated parsers can be used both at run and at compile time.

- NPeg offers various methods for tracing, optimizing and debugging your
  parsers.

## Quickstart

Here is a simple example showing the power of NPeg: The macro `peg` compiles a
grammar definition into a `parser` object, which is used to match a string and
place the key-value pairs into the Nim table `words`:

```nim
import npeg, strutils, tables

var words = initTable[string, int]()

let parser = peg "pairs":
  pairs <- pair * *(',' * pair) * !1
  word <- +Alpha
  number <- +Digit
  pair <- >word * '=' * >number:
    words[$1] = parseInt($2)

doAssert parser.match("one=1,two=2,three=3,four=4").ok
echo words
```

Output:

```nim
{"two": 2, "three": 3, "one": 1, "four": 4}
```

A brief explanation of the above code:

* The macro `peg` is used to create a parser object, which uses `pairs` as the
  initial grammar rule to match

* The rule `pairs` matches one `pair`, followed by zero or more times (`*`) a
  comma followed by a `pair`.

* The rules `word` and `number` match a sequence of one or more (`+`)
  alphabetic characters or digits, respectively. The `Alpha` and `Digit` rules
  are pre-defined rules matching the character classes `{'A'..'Z','a'..'z'}` and 
  `{'0'..'9'}`

* The rule `pair` matches a `word`, followed by an equals sign (`=`), followed
  by a `number.

* The `word` and `number` in the `pair` rule are captured with the `>`
  operator. The Nim code fragment below this rule is executed for every match,
  and stores the captured word and number in the `words` Nim table.

## Usage

The `patt()` and `peg()` macros can be used to compile parser functions:

- `patt()` creates a parser from a single anonymous pattern

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
  occured.

The following procs are available to retrieve the captured results:

```nim
proc captures(m: MatchResult): seq[string]
proc capturesJson(m: MatchResult): JsonNode
proc capturesAST(m: MatchResult): ASTnode
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

The order in which the grammar patterns are defined affects the generated parser.
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

- NPeg uses prefixes instead of suffixes for `*`, `+`, `-` and `?`
- Ordered choice uses `|` instead of `/` because of operator precedence
- The explicit `*` infix operator is used for sequences

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

String captures:  

  >P              # Captures the string matching  P 

AST captures (Experimental)

  A("Id", P)      # Stores all captures of P in AST node `Id`

Json captures:

  Js(P)           # Produces a JString from the string matching  P 
  Ji(P)           # Produces a JInteger from the string matching  P 
  Jf(P)           # Produces a JFloat from the string matching  P 
  Jb(P)           # Produces a JBool from the string matching  P 
  Ja()            # Produces a new JArray
  Jo()            # Produces a new JObject
  Jt("tag", P)    # Stores capture P in the field "tag" of the outer JObject
  Jt(P)           # Stores the second Json capture of P in the outer JObject
                  # using the first Json capure of P as the tag.

Back references:

  R("tag", P)     # Create a named reference for pattern P
  R("tag")        # Matches the given named reference

Error handling:

  E"msg"          # Raise an execption with the given message
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

Atoms are the basic building blocks for a grammer, describing the parts of the
subject that should be matched.

- Integer literal: `0` / `1` / `n`

  The int literal atom `n` matches exactly n number of bytes. `0` always matches,
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

NPeg provides various prefix, infix and suffix operators. These operators
combine or transform one or more patterns into expressions, building larger
patterns.

- Concatenation: `P1 * P2`

  The pattern `P1 * P2` returns a new pattern that matches only if first `P1` matches,
  followed by `P2`.

  For example, `"foo" * "bar"` would only match the string `"foobar"`


- Ordered choice: `P1 | P2`

  The pattern `P1 | P2` tries to first match pattern `P1`. If this succeeds,
  matching will proceed without trying `P2`. Only if `P1` can not be matched,
  NPeg will backtrack and try to match `P2` instead.

  For example `("foo" | "bar") * "fizz"` would match both `"foofizz"` and `"barfizz"`

  NPeg optimizes the `|` operator for characters and character sets: The
  pattern `'a' | 'b' | 'c'` will be rewritten to a character set `{'a','b','c'}`


- Difference: `P1 - P2`

  The pattern `P1 - P2` matches `P1` *only* if `P2` does not match. This is
  equivalent to `!P2 * P1`

  NPeg optimizes the `-` operator for characters and character sets: The
  pattern `{'a','b','c'} - 'b'` will be rewritten to the character set `{'a','c'}`


- Grouping: `(P)`

  Brackets are used to group patterns similar to normal arithmetic expressions.


- Not-predicate: `!P`

  The pattern `!P` returns a pattern that matches only if the input does not match `P`.
  In contrast to most other patterns, this pattern does not consume any input.

  A common usage for this operator is the pattern `!1`, meaning "only succeed if there
  is not a single character left to match" - which is only true for the end of the string.


- And-predicate: `&P`

  The pattern `&P` matches only if the input matches `P`, but will *not*
  consume any input. This is equivalent to `!!P`


- Optional: `?P`

  The pattern `?P` matches if `P` can be matched zero or more times, so essentially
  succeeds if `P` either matches or not.

  For example, `?"foo" * bar"` matches both `"foobar"` and `"bar"`


- Match zero or more times: `*P`

  The pattern `*P` tries to match as many occurrences of pattern `P` as
  possible - this operator always behaves *greedily*.

  For example, `*"foo" * "bar"` matches `"bar"`, `"fooboar"`, `"foofoobar"`, etc


- Match one or more times: `+P`

  The pattern `+P` matches `P` at least once, but also more times. It is equivalent
  to the `P * *P` - this operator always behave *greedily*


- Search: `@P`

  This operator is syntactic sugar for the operation of searching `s <- P | 1 * s`,
  which translates to "try to match `P`, and if this fails, consume 1 byte and
  try again".

  Note that this operator does not allow capturing the skipped data up to the
  match; if his is required you can manually construct a grammar to do this.


- Match exactly `n` times: `P[n]`

  The pattern `P[n]` matches `P` exactly `n` times.

  For example, `"foo"[3]` only matches the string `"foofoofoo"`


- Match `m` to `n` times: `P[m..n]`

  The pattern `P[m..n]` matches `P` at least `m` and at most `n` times.

  For example, `"foo[1,3]"` matches `"foo"`, `"foofoo"` and `"foofoofo"`


## Captures

NPeg supports a number of ways to capture data when parsing a string. The various
capture methods are described here, including a concise example.

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


### AST (Abstract Syntax Tree) captures

Note: AST captures is an experimental feature, the implementation or API might
change in the future.

NPeg has a simple mechanism for storing captures in a tree data structure,
allowing building of abstract syntax trees straight from the parser.

The basic AST node has the following layout:

```nim
ASTNode* = ref object
  id*: string           # user assigned AST node ID
  val*: string          # string capture
  kids*: seq[ASTNode]   # child nodes
```

To parse a subject and capture strings into a tree of `ASTNode`s, use the
`A(id, p)` operator:

- The `A(id, p)` operator creates a new `ASTNode` with the given identifier
- The first string capture (`>`) inside pattern `p` will be assigned to the 
  `val` field of the AST node
- All nested `ASTnode`s in pattern `p` will be added to the nodes `kids` seq.

The following snippet shows an example of creating an AST from arithmetic
expressions while properly handling operator precedence;

```nim
type Kind* = enum kInt, kAdd, kSub, kMul, kDiv

let s = peg "line":
  line     <- exp * !1
  number   <- A(kInt, >+Digit)
  add      <- A(kAdd, term * '+' * exp)
  sub      <- A(kSub, term * '-' * exp)
  mul      <- A(kMul, factor * '*' * term)
  divi     <- A(kDiv, factor * '/' * term)
  exp      <- add | sub | term
  term     <- mul | divi | factor
  factor   <- number | '(' * exp * ')'

let r = s.match("1+2*(3+4+9)+5*6")
let ast = r.capturesAST()
echo ast
```

This will generate an AST tree with the following layout:

```
       +
      / \
     1   + 
        / \
       /   \
      /     *
     *     / \
    / \   5   6
   2   +
      / \
     3   +
        / \
       4   9
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
let parser = peg "pairs":
  pairs <- Jo(pair * *(',' * pair) * !1)
  word <- +Alpha
  number <- +Digit
  pair <- Jt(Js(word) * '=' * Ji(number))

let r = parser.match(data)
echo r.capturesJson
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


### Code block captures

Code block captures offer the most flexibility for accessing matched data in
NPeg. This allows you to define a grammar with embedded Nim code for handling
the data during parsing.

Note that for code block captures, the Nim code gets executed during parsing,
*even if the match is part of a pattern that fails and is later backtracked*

When a grammar rule ends with a colon `:`, the next indented block in the
grammar is interpreted as Nim code, which gets executed when the rule has been
matched. Any string captures that were made inside the rule are available to
the Nim code in the injected variable `capture[]` of type `seq[Capture]`:

```
type Capture = object
  s*: string      # The captured string
  si*: int        # The index of the captured string in the subject
```

For convenience there is syntactic sugar available in the code block which
allows to use fake variables `$1` to `$9` to be used to access the captured
strings. Some important notes about this notation:

- Offset difference: The first capture string from `capture[0]` is available in
  the fake variable `$1`.

- Operator precedence: the dollar-variables might need parentheses or different
  ordering in some cases, for example `$1.parseInt` should be written as
  `parseInt($1)`)

Code block captures consume all embedded string captures, so these captures
will no longer be available after matching.

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

After the parsing finished, the `words` table will now contain

```nim
{"two": 2, "three": 3, "one": 1, "four": 4}
```

#### Custom match validations

Code block captures can be used for additional validation of a captured string:
the code block can call the function `validate(bool)` to indicate if the match
should succeed or fail. Failing matches are handled as if the capture itself
failed and will result in the usual backtracking. When the `validate()` function
is not called, the match will succeed implicitly.

For example, the following rule will check if a passed number is a valid
`uint8` number:

```
   uint8 <- >Digit[1..3]:
     let v = parseInt($a)
     validate v>=0 and v<=255
```


#### Generic pegs and passing state

Note: This is an experimental feature, the implementation or API might change
in the future. I'm also looking for a better name for this feature.

NPeg parsers can be instantiated as generics which allows passing of data of a
specific type to the `match()` function, this value is then available inside
code blocks as a variable. This mitigates the need for global variables for
storing data in access captures.

The syntax for defining a generic grammar is as follows:

```
peg(name, identifier: Type)
```

For example, the above parser can be rewritten using a generic parser as such:

```nim
type Dict = Table[string, int]

let parser = peg("pairs" userdata: Dict):
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
  be refered to by name in other places in the grammar.

* The pattern `R(name)` matches the contents of the named reference that
  earlier been stored with `R(name, P)` pattern.

For example, the following rule will match only a string which will have the 
same character in the first and last position:

```
patt R("c", 1) * *(1 - R("c")) * R("c") * !1
```

The first part of the rule `R("c", 1)` will match any character, and store this
in the named reference `c`. The second part will match a sequence of zero or more
characters that do not match reference `c`, followed by reference `c`.


## More about grammars


### Ordering of rules in a grammar

Repetitive inlining of rules might cause a grammar to grow too large, resulting
in a huge executable size and slow compilation. NPeg tries to mitigate this in
two ways:

* Patterns that are too large will not be inlined, even if the above ordering
  rules apply.

* NPeg checks the size of the total grammar, and if it thinks it is too large
  it will fail compilation with the error message `NPeg: grammar too complex`

Check the section "Compile-time configuration" below for more details about too
complex grammars.

The parser size and performance depends on many factors; when performance
and/or code size matters, it pays to experiment with different orderings and
measure the results.

When in doubt, check the generated parser instructions by compiling with the
`-d:npegTrace` or `-d:npegDumpDot` flags - see the section Tracing and
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


### Templates, or parameterised rules

When building more complex grammars you may find yourself duplicating certain
constructs in patterns over and over again. To avoid code repetition (DRY),
NPeg provides a simple mechanism to allow the creation of parameterized rules.
In good Nim-fashion these rules are called "templates". Templates are defined
just like normal rules, but have a list of arguments, which are referred to in
the rule. Technically, templates just perform a basic search-and-replace
operation: every occurence of a named argument is replaced by the exact pattern
passed to the template when called.

For example, consider the following grammar:

```
numberList <- +Digit * *( ',' * +Digit)
wordList <- +Alpha * *( ',' * +Alpha)
```

This snippet uses a common pattern twice for matching lists: `p * *( ',' * p)`.
This matches pattern `p`, followed by zero or more occurrences of a comma
followed by pattern `p`. For example, `numberList` will match the string
`1,22,3`.

The above example can be parameterized with a template like this:

```
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

```
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
form `libraryname.patternname`, by which they can be refered to at a later
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
added to NPegs global pattern library. For example:

```
import npeg/lib/uri
```


### Library rule overriding/shadowing

To allow the user to add custom captures to imported grammars or rules, it is
possible to *override* or *shadow* an existing rule in a grammer.

Overriding will replace the rule from the library with the provided new rule,
allowing the caller to change parts of an imported grammar. A overridden rule
is allowed to reference the original rule by name, which will cause the new
rule to *shadow* the original rule. This will effectively rename the original
rule and replace it with the newly defined rule which will call the original
refered rule.

For example, the following snippet will reuse the grammar from the `uri`
library and capture some parts of the URI in a nim object:

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


## Some notes on using PEGs


### Achoring and searching

Unlike regular expressions, PEGs are always matched in *anchored* mode only: the
defined pattern is matched from the start of the subject string. For example,
the pattern `"bar"` does not match the string `"foobar"`.

To search for a pattern in a stream, a construct like this can be used:

```nim
p <- "bar"
search <- p | 1 * search
```

The above grammar first tries to match pattern `p`, or if that fails, matches
any character `1` and recurs back to itself. Because searching is a common
operation, NPeg provides the builtin `@P` operator for this.


### End of string

PEGs do not care what is in the subject string after the matching succeeds. For
example, the rule `"foo"` happily matches the string `"foobar"`. To make sure
the pattern matches the end of string, this has to be made explicit in the
pattern.

The idiomatic notation for this is `!1`, meaning "only succeed if there is not
a single character left to match" - which is only true for the end of the
string.


### Parsing error handling

NPeg offers a number of ways to handle errors during parsing a subject string:

The `ok` field in the `MatchResult` indicates if the parser was successful:
when the complete pattern has been mached this value will be set to `true`,
if the complete pattern did not match the subject the value will be `false`.

In addition to the `ok` field, the `matchMax` field indicates the maximum
offset into the subject the parser was able to match the string. If the
matching succeeded `matchMax` equals the total length of the subject, if the
matching failed, the value of `matchMax` is usually a good indication of where
in the subject string the error occurred.

When, during matching, the parser reaches an `E"message"` atom in the grammar,
NPeg will raise an `NPegException` exception with the given message. The typical
use case for this atom is to be combine with the ordered choice `|` operator to
generate helpful error messages. The following example illustrates this:

```nim
let parser = peg "list":
  list <- word * *(comma * word) * eof
  eof <- !1
  comma <- ','
  word <- +{'a'..'z'} | E"word"

echo parser.match("one,two,three,")
```

The rule `word` looks for a sequence of one or more letters (`+{'a'..'z'}`). If
can this not be matched the `E"word"` matches instead, raising an exception:

```
Error: unhandled exception: Parsing error at #14: expected "word" [NPegException]
```

The `NPegException` type contains the same two fields as `MatchResult` to indicate
where in the subject string the match failed: `matchLen` and `matchMax`:

```nim
let a = patt 4 * E"boom"
try:
  doAssert a.match("12345").ok
except NPegException as e:
  echo "Parsing failed at position ", e.matchMax
```

### Left recursion

NPeg does not support left recursion (this applies to PEGs in general). For
example, the rule

```nim
A <- A / 'a'
```

will cause an infinite loop because it allows for left-recursion of the
non-terminal `A`.

Similarly, the grammar

```nim
A <- B / 'a' A
B <- A
```

is problematic because it is mutually left-recursive through the non-terminal
`B`.

Note that loops of patterns that can match the empty string will not result in
the expected behaviour. For example, the rule `*0` will cause the parser to
stall and go into an infinite loop.


### UTF-8 / Unicode

NPeg has no built-in support for unicode or UTF-8, instead is simply able to
parse UTF-8 documents just as like any other string. NPeg comes with a simple
utf8 grammar library which should simplify common operations like matching a
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

### Grammar graph

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

Large rules result in larger generated code and slow compile times. Rule size can
generally be decreased by changing the rule order in a grammar to allow NPeg to
call rules instead of inlining them.


### Tracing

When compiled with `-d:npegTrace`, NPeg will dump its intermediate representation
of the compiled PEG, and will dump a trace of the execution during matching.
These traces can be used for debugging or optimization of a grammar.

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

1. the current instruction pointer, which maps to the compile time dump
2. the index into the subject
3. the substring of the subject
4. the name of the rule from which this instruction originated
5. the instruction being executed
6. the backtrace stack depth

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

* `-d:npegTrace`: Enable compile time and run time tracing. Please refer to the 
  section 'Tracing' for more details

* `-d:npegExpand`: Dump the generated Nim code for all parsers defined in the
  program. Ment for Npeg development debugging purposes only.

* `-d:npegDebug`: Enable more debug info. Ment for Npeg development debugging
  purposes only.


## Random stuff and frequently asked questions


### Why does NPeg not support regular PEG syntax?

The NPeg syntax is similar, but not exactly the same as the official PEG
syntax: it uses some different operators, and prefix instead of postfix
operators. The reason for this is that the NPeg grammar is parsed by a Nim
macro in order to allow code block captures to embed Nim code, which puts some
limitations on the available syntax. Also, NPegs operators are chosen so that
they have the right precedence for PEGs.


### Can NPeg be used to parse EBNF grammars?

Almost, but not quite. Although PEGS and EBNF look quite similar, there are
some subtle but important diferences which do not allow a literal translation
from EBNF to PEG. Notable differences are left recursion and ordered choice.
Also, see "From EBNF to PEG" from Roman R. Redziejowski.



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


### A complete Json parser

The following PEG defines a complete parser for the Json language - it will not produce
any captures, but simple traverse and validate the document:

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

