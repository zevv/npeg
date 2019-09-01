
#
# This library file is special: it is imported by default, and provides rules
# which do not live in a separate namespace.
#

when defined(nimHasUsed): {.used.}

import npeg

grammar "":
  Alnum  <- {'A'..'Z','a'..'z','0'..'9'} # Alphanumeric characters
  Alpha  <- {'A'..'Z','a'..'z'}          # Alphabetic characters
  Blank  <- {' ','\t'}                   # Space and tab
  Cntrl  <- {'\x00'..'\x1f','\x7f'}      # Control characters
  Digit  <- {'0'..'9'}                   # Digits
  Graph  <- {'\x21'..'\x7e'}             # Visible characters
  Lower  <- {'a'..'z'}                   # Lowercase characters
  Print  <- {'\x21'..'\x7e',' '}         # Visible characters and spaces
  Space  <- {'\9'..'\13',' '}            # Whitespace characters
  Upper  <- {'A'..'Z'}                   # Uppercase characters
  Xdigit <- {'A'..'F','a'..'f','0'..'9'} # Hexadecimal digits

