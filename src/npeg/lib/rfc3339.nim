
#
# This library provides a number of common types
#

import npeg

when defined(nimHasUsed): {.used.}

grammar "rfc3339":

   date_fullyear   <- Digit[4]
   date_month      <- Digit[2]  # 01-12
   date_mday       <- Digit[2]  # 01-28, 01-29, 01-30, 01-31 based on
                                # month/year
   time_hour       <- Digit[2]  # 00-23
   time_minute     <- Digit[2]  # 00-59
   time_second     <- Digit[2]  # 00-58, 00-59, 00-60 based on leap second
                               # rules
   time_secfrac    <- "." * +Digit
   time_numoffset  <- ("+" | "-") * time_hour * ":" * time_minute
   time_offset     <- "Z" | time_numoffset

   partial_time    <- time_hour * ":" * time_minute * ":" * time_second * ?time_secfrac
   full_date       <- date_fullyear * "-" * date_month * "-" * date_mday
   full_time       <- partial_time * time_offset

   date_time       <- full_date * ("T" | " ") * full_time
