import unittest
import npeg

const verbose = false

abortOnError = true


suite "npeg":

  test "literal string":
    let s = peg "test":
      test <- "abc"
    doAssert s "abc"

  test "simple grammar":
    let s = peg "aap":
      a <- "a"
      aap <- a * *('(' * aap * ')')
    doAssert s("a(a)((a))")

  test "HTTP parser":

    let data ="""
POST flop HTTP/1.1
Content-Type: text/plain
content-length: 23
"""
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

    doAssert s(data)

  test "expression parser":
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

    doAssert s "1"
    doAssert s "1+1"
    doAssert s "1+1*1"
    doAssert s "(1+1)*1"
    doAssert s "13 + 5 * (2+1)"

