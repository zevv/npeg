
#
# This library provides a number of common types
#

import npeg

when defined(nimHasUsed): {.used.}

template checkRange*(T: typedesc, parseFn: untyped, s: string): bool =
  let v = parseFn(s).BiggestInt
  v >= T.low.BiggestInt and v <= T.high.BiggestInt

grammar "types":

  bool    <- "true" | "false"

  # Unsigned decimal

  uint    <- +Digit
  uint8   <- >+uint: validate checkRange(uint8,  parseInt, $1)
  uint16  <- >+uint: validate checkRange(uint16, parseInt, $1)
  uint32  <- >+uint: validate checkRange(uint32, parseInt, $1)

  # Signed decimal

  int     <- ?'-' * uint
  int8    <- >int: validate checkRange(int8,   parseInt, $1)
  int16   <- >int: validate checkRange(int16,  parseInt, $1)
  int32   <- >int: validate checkRange(int32,  parseInt, $1)
  int64   <- >int: validate checkRange(int64,  parseInt, $1)

  # Hexadecimal

  hex    <- '0' * {'x','X'} * +Digit
  hex8   <- >+uhex: validate checkRange(uint8,  parseHexInt, $1)
  hex16  <- >+uhex: validate checkRange(uint16, parseHexInt, $1)
  hex32  <- >+uhex: validate checkRange(uint32, parseHexInt, $1)

