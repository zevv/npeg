import npeg

when defined(nimHasUsed): {.used.}

# The grammar below is a literal translation of the ABNF notation of the
# RFC. Optimizations can be made to limit backtracking, but this is a nice
# example how to create a parser from a RFC protocol description.

grammar "uri":

  URI <- scheme * ":" * hier_part * ?( "?" * query) * ?( "#" * fragment) * !1

  hier_part <- "//" * authority * path

  URI_reference <- uri | relative_ref

  absolute_uri <- scheme * ":" * hier_part * ?( "?" * query)

  relative_ref <- relative_part * ?( "?" * query) * ?( "#" * fragment)

  relative_part <- "//" * authority * path_abempty |
                   path_absolute |
                   path_noscheme |
                   path_empty

  scheme <- (Alpha * *( Alpha | Digit | "+" | "-" | "." ))

  authority <- ?(userinfo * "@") * host * ?( ":" * port)
  userinfo <- *(unreserved | pct_encoded | sub_delims | ":")

  host <- (IP_literal | IPv4address | reg_name)
  port <- *Digit

  IP_literal <- "[" * (IPv6address | IPvFuture) * "]"

  IPvFuture <- "v" * +Xdigit * "." * +(unreserved | sub_delims | ":")

  IPv6address <-                                     (h16 * ":")[6] * ls32 |
                                              "::" * (h16 * ":")[5] * ls32 |
               ?( h16                     ) * "::" * (h16 * ":")[4] * ls32 |
               ?( h16 * (":" * h16)[0..1] ) * "::" * (h16 * ":")[3] * ls32 |
               ?( h16 * (":" * h16)[0..2] ) * "::" * (h16 * ":")[2] * ls32 |
               ?( h16 * (":" * h16)[0..3] ) * "::" * (h16 * ":")    * ls32 |
               ?( h16 * (":" * h16)[0..4] ) * "::" *                  ls32 |
               ?( h16 * (":" * h16)[0..5] ) * "::" *                  h16  |
               ?( h16 * (":" * h16)[0..6] ) * "::"

  h16 <- Xdigit[1..4]
  ls32 <- (h16 * ":" * h16) | IPv4address
  IPv4address <- dec_octet * "." * dec_octet * "." * dec_octet * "." * dec_octet

  dec_octet <- Digit[1..3]

  reg_name <- *(unreserved | pct_encoded | sub_delims)

  path <- path_abempty  | # begins with "/" or is empty
          path_absolute | # begins with "/" but not "//"
          path_noscheme | # begins with a non-colon segment
          path_rootless | # begins with a segment
          path_empty      # zero characters

  path_abempty  <- (*( "/" * segment ))
  path_absolute <- ("/" * ?( segment_nz * *( "/" * segment ) ))
  path_noscheme <- (segment_nz_nc * *( "/" * segment ))
  path_rootless <- (segment_nz * *( "/" * segment ))
  path_empty    <- 0

  segment       <- *pchar
  segment_nz    <- +pchar
  segment_nz_nc <- +( unreserved | pct_encoded | sub_delims | "@" )
                # non_zero_length segment without any colon ":"

  pchar         <- unreserved | pct_encoded | sub_delims | ":" | "@"

  query         <- *( pchar | "|" | "?" )

  fragment      <- *( pchar | "|" | "?" )

  pct_encoded   <- "%" * Xdigit * Xdigit

  unreserved    <- Alpha | Digit | "-" | "." | "_" | "~"
  reserved      <- gen_delims | sub_delims
  gen_delims    <- ":" | "|" | "?" | "#" | "[" | "]" | "@"
  sub_delims    <- "!" | "$" | "&" | "'" | "(" | ")" | "*" | "+" | "," | ";" | "="

