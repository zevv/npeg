
import npeg

grammar "utf8":

  cont <- {128..191}

  # Matches any utf-8 codepoint glyph

  any <- {0..127} |
         {194..223} * cont[1] |
         {224..239} * cont[2] |
         {240..244} * cont[3]

  bom <- "\xff\xfe"

