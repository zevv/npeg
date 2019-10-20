
import npeg

when defined(nimHasUsed): {.used.}

grammar "utf8":

  cont <- {128..191}

  # Matches any utf-8 codepoint glyph

  any <- {0..127} |
         {194..223} * cont[1] |
         {224..239} * cont[2] |
         {240..244} * cont[3]

  bom <- "\xff\xfe"

  # Check for UTF-8 character classes. Depends on the tables from
  # the nim unicode module

  space <- >any: validate unicode.isSpace($1)
  lower <- >any: validate unicode.isLower(runeAt($1, 0))
  upper <- >any: validate unicode.isUpper(runeAt($1, 0))
  alpha <- >any: validate unicode.isAlpha(runeAt($1, 0))
  title <- >any: validate unicode.isTitle(runeAt($1, 0))
