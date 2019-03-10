
# NPeg

NPeg is an early stage pure Nim pattern-matching library.

The NPeg library is an implementation of Parsing Expression Grammars for the
Lua language.  Unlike other PEG implementations, which aim at parsing, NPeg
aims at pattern matching. Therefore, it turns PEG inside out: while PEGs define
grammars using pattern expressions as an auxiliary construction, in NPeg the
main construction is the pattern, and grammars are only a particular way to
create patterns.



## Status

Work in progress.

## Docs

Implemented:

```nim
P(string)       # Matches string literally
I(string)       # Matches string literally, case insensitive
P(n)            # Matches exactly n characters
S(string)       # Matches any character in string (Set)
R("xy")         # Matches any character between x and y (Range)
patt^n          # Matches at least n repetitions of patt
patt^-n         # Matches at most n repetitions of patt
patt1 * patt2   # Matches patt1 followed by patt2
patt1 + patt2   # Matches patt1 or patt2 (ordered choice)
patt1 - patt2   # Matches patt1 if patt2 does not match
-patt           # Equivalent to ("" - patt)
C(patt)         # Create a capture
```

On the whish list:

* Implement non-terminals to be able to construct recursive grammars

* Much more elaborate captures - ideally, NPeg should be able to capture
  into Nim objects and allow to build ASTs on the fly

* Compile time transcoding of the PEG VM code into Nim for absolute 
  top speed parsing

* Provide an alternative method for constructing PEGS through a Nim 
  macro based DSL


## Examples

Matches valid identifiers "a letter or an underscore followed by zero or more
alphanumeric characters or underscores.":

```nim
  let alpha = R("az") + R("AZ")
  let digit = R("09")
  let alphanum = alpha + digit
  let underscore = P"_"
  let identifier = (alpha + underscore) * (alphanum + underscore)^0

  doAssert identifier.match("myId_3")
```

Matches valid decimal, floating point and scientific notation numbers:

```nim
  let digit = R("09")

  # Matches: 10, -10, 0
  let integer =
    (S("+-") ^ -1) *
    (digit   ^  1)

  # Matches: .6, .899, .9999873
  let fractional =
    (P(".")   ) *
    (digit ^ 1)

  # Matches: 55.97, -90.8, .9 
  let decimal = 
    (integer *                     # Integer
    (fractional ^ -1)) +           # Fractional
    ((S("+-") ^ -1) * fractional)  # Completely fractional number

  # Matches: 60.9e07, 9e-4, 681E09 
  let scientific = 
    decimal * # Decimal number
    S("Ee") *        # E or e
    integer   # Exponent

  # Matches all of the above
  # Decimal allows for everything else, and scientific matches scientific
  let number = scientific + decimal

  doAssert number.match("1")
  doAssert number.match("1.0")
  doAssert number.match("3.141592")
  doAssert number.match("-5")
  doAssert number.match("-5.5")
  doAssert number.match("1e3")
  doAssert number.match("1.0e3")
  doAssert number.match("-1.0e-6")
```


[More Examples](https://github.com/zevv/npeg/blob/master/tests/test1.nim) are
available in the tests directory, run with `nimble test`.


