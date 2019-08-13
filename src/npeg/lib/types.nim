
#
# This library provides a number of common types
#

import npeg
import strutils

template checkRange*(T: typedesc, parseFn: untyped, s: string): bool =
  let v = parseFn(s).BiggestInt
  v >= T.low.BiggestInt and v <= T.high.BiggestInt

grammar "types":

  bool    <- "true" | "false"

  # Unsigned decimal

  uint    <- +Digit
  uint8   <- >+uint: return checkRange(uint8,  parseInt, $1)
  uint16  <- >+uint: return checkRange(uint16, parseInt, $1)
  uint32  <- >+uint: return checkRange(uint32, parseInt, $1)
  uint64  <- >+uint: return checkRange(uint64, parseInt, $1)

  # Signed decimal

  int     <- ?'-' * uint
  int8    <- >int: return checkRange(int8,   parseInt, $1)
  int16   <- >int: return checkRange(int16,  parseInt, $1)
  int32   <- >int: return checkRange(int32,  parseInt, $1)
  int64   <- >int: return checkRange(int64,  parseInt, $1)

  # Hexadecimal

  hex    <- '0' * {'x','X'} * +Digit
  hex8   <- >+uhex: return checkRange(uint8,  parseHexInt, $1)
  hex16  <- >+uhex: return checkRange(uint16, parseHexInt, $1)
  hex32  <- >+uhex: return checkRange(uint32, parseHexInt, $1)
  hex64  <- >+uhex: return checkRange(uint64, parseHexInt, $1)

