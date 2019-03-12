
import npeg


when false:
  block:
    let s = peg "aap":
      a <- "a"
      aap <- a * *('(' * aap * ')')
    echo s("a(a)((a))")


when true:
  block:
    let s = peg "http":
      space                 <- ' '
      crlf                  <- '\n' | "\r\n"
      meth                  <- "GET" | "POST" | "PUT"
      proto                 <- "HTTP"
      version               <- "1.0" | "1.1"
      alpha                 <- {'a'..'z','A'..'Z'}
      digit                 <- {'0'..'9'}
      url                   <- +alpha
      eof                   <- -{}

      req                   <- meth * space * url * space * proto * "/" * version

      header_content_length <- i"Content-Length: " * +digit
      header_other          <- +(alpha | '-') * ": " * +({}-crlf)
    
      header                <- header_content_length | header_other
      http                  <- req * crlf * *(header * crlf) * eof

    echo s """
POST flop HTTP/1.1
Content-Type: text/plain
content-length: 23
"""

when false:
  block:
    let s = peg "line":
      ws       <- *' '
      digit    <- {'0'..'9'} * ws
      number   <- +digit * ws
      termOp   <- {'+', '-'} * ws
      factorOp <- {'*', '/'} * ws
      open     <- '(' * ws
      close    <- ')' * ws
      eol      <- -{}
      exp      <- term * *(termOp * term)
      term     <- factor * *(factorOp * factor)
      factor   <- number | (open * exp * close)
      line     <- ws * exp * eol
    echo s("13 + 5 * (2+1)")

