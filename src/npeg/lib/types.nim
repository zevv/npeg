
#
# This library provides a number of basic types
#

import npeg
import strutils

template checkRange*[T](s: string): bool =
  let v = parseBiggestInt(s)
  v >= T.low.BiggestInt and v <= T.high.BiggestInt

grammar "types":
  bool    <- "true" | "false"
  uint8   <- >+Digit: return checkRange[uint8]($1)
  uint16  <- >+Digit: return checkRange[uint16]($1)
  uint32  <- >+Digit: return checkRange[uint32]($1)
  uint64  <- >+Digit: return checkRange[uint64]($1)
  int8    <- >+Digit: return checkRange[int8]($1)
  int16   <- >+Digit: return checkRange[int16]($1)
  int32   <- >+Digit: return checkRange[int32]($1)
  int64   <- >+Digit: return checkRange[int64]($1)
