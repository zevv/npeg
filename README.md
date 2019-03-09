
# nPEG

nPEG is an early stage pure Nim pattern-matching library.


## Status

Work in progress.

## Docs

Implemented:

```nim
P(string)       # Matches string literally
P(n)            # Matches exactly n characters
S(string)       # Matches any character in string (Set)
R("xy")         # Matches any character between x and y (Range)
patt^n          # Matches at least n repetitions of patt
patt^-n         # Matches at most n repetitions of patt
patt1 * patt2   # Matches patt1 followed by patt2
patt1 + patt2   # Matches patt1 or patt2 (ordered choice)
```


Not yet implemented:

```nim
patt1 - patt2   # Matches patt1 if patt2 does not match
-patt           # Equivalent to ("" - patt)
#patt           # Matches patt but consumes no input
lpeg.B(patt)    # Matches patt behind the current position, consuming no input
```


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


