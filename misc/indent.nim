  # Indent syntax

  let data = """
a=123
b=
  c=567
  e=42
f=18
g=
  b=44
  c=22
"""

  var indentStack = @[""]
  template top[T](s: seq[T]): T = s[s.high]


  let p = peg doc:
    doc <- pairs * !1
    pairs <- pair * *('\n' * pair)
    pair <- indSame * key * '=' * val
    indentPairs <- '\n' * &indIn * pairs * &('\n' * indOut)
    key <- +Alpha:
      echo "key ", $0
    number <- +Digit:
      echo "val ", $0
    val <- number | indentPairs

    indSame <- *' ':
      validate $0 == indentStack.top

    indIn <- *' ':
      validate len($0) > len(indentStack.top)
      indentStack.add $0
    
    indOut <- *' ':
      discard indentStack.pop
      validate $0 == indentStack.top

  echo p.match(data).ok
