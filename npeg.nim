
import strutils

type

  Opcode = enum
    IChar, IEnd, ISet

  Inst = object
    case code: Opcode
      of IEnd:
        discard
      of IChar:
        c: char
      of ISet:
        cs: ref set[char]

  Patt = ref object
    inst: seq[Inst]



proc newPatt(len: int): Patt =
  new result
  result.inst.setLen(len+1)
  result.inst[len].code = IEnd


proc newCharset(): Patt =
  new result
  result.inst.setLen(1)
  result.inst[0].code = ISet
  new result.inst[0].cs


proc getPatt(s: string): Patt =
  result = newPatt(s.len)
  for i in 0..<s.len:
    result.inst[i].code = IChar
    result.inst[i].c = s[i]


proc P(s: string): Patt =
  getPatt(s)


proc S(s: string): Patt = 
  result = newCharset()
  for c in s.items:
    result.inst[0].cs[].incl c


proc `$`(inst: Inst): string =
  result.add $inst.code & " "
  case inst.code:
    of IChar: result.add "'" & inst.c & "'"
    of ISet:
      result.add "["
      for c in char.low..char.high:
        if c in inst.cs[]:
          result.add c
      result.add "]"
    else: discard


proc `$`(p: Patt): string =
  for i, inst in p.inst:
    result.add $i & ": " & $inst & "\n"


proc match(p: Patt, s: string) =
  var oi = 0
  var os = 0
  var fail = false

  while os < s.len and not fail:
    let inst = p.inst[oi]

    echo "i: " & $inst & " | s: " & s[os..<s.len]

    case inst.code:

      of IEnd:
        break

      of IChar:
        if s[os] != inst.c:
          fail = true
        else:
          inc oi
          inc os

      of ISet:
        if s[os] notin inst.cs[]:
          fail = true
        else:
          inc oi
          inc os

  if fail:
    echo "fail"

  discard



#let s = P"abc"
let s = S"bca"

s.match("a")

# vi: ft=nim et ts=2 sw=2

