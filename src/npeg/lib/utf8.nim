
import npeg
import unicode

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

  space <- >utf8.any: return unicode.isSpace(runeAt($1, 0))
  lower <- >utf8.any: return unicode.isLower(runeAt($1, 0))
  upper <- >utf8.any: return unicode.isUpper(runeAt($1, 0))
  alpha <- >utf8.any: return unicode.isAlpha(runeAt($1, 0))
  title <- >utf8.any: return unicode.isTitle(runeAt($1, 0))
