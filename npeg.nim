
import strutils

const
  debug = true

type

  Opcode = enum
    iChar, iSet, iJump, iChoice, iCall, iReturn, iCommit, iFail, iAny

  Inst = object
    case code: Opcode
      of iChar:
        c: char
      of iSet:
        cs: set[char]
      of iChoice, iJump, iCall, iCommit:
        offset: int
      of iReturn, iFail:
        discard
      of iAny:
        count: int

  StackFrame = object
    so: int # Source offset
    ip: int # Instruction pointer

  Patt = ref object
    inst: seq[Inst]


#
# Helper functions
#

proc dumpInst(inst: Inst, ip: int): string =
  result.add $inst.code & " "
  case inst.code:
    of iChar:
      result.add "'" & inst.c & "'"
    of iSet:
      result.add "["
      for c in char.low..char.high:
        if c in inst.cs:
          result.add c
      result.add "]"
    of iChoice, iJump, iCall, iCommit:
      result.add $(ip + inst.offset)
    of iReturn, iFail:
      discard
    of iAny:
      result.add $inst.count

proc `$`*(p: Patt): string =
  for ip, inst in p.inst:
    if ip != 0: result.add "\n"
    result.add $ip & ": " & $dumpInst(inst, ip)

proc len(p: Patt): int = p.inst.len


#
# Constructors
#

proc P*(s: string): Patt =
  ## Matches string `s` literally
  new result
  for c in s.items:
    result.inst.add Inst(code: iChar, c: c)

proc P*(count: int): Patt =
  ## Matches exactly `count` characters
  new result
  result.inst.add Inst(code: iAny, count: count)

proc S*(s: string): Patt = 
  ## Matches any character in the string `s` (Set)
  var cs: set[char]
  for c in s.items:
    cs.incl c
  new result
  result.inst.add Inst(code: iSet, cs: cs)

proc R*(s: string): Patt =
  ## `"xy"` matches any character between x and y (Range)
  var cs: set[char]
  doAssert s.len == 2
  for c in s[0]..s[1]:
    cs.incl c
  new result
  result.inst.add Inst(code: iSet, cs: cs)


#
# Operators for building grammars
#

proc `*`*(p1, p2: Patt): Patt =
  ## Matches pattern `p1` followed by pattern `p2`
  new result
  result.inst.add p1.inst
  result.inst.add p2.inst

proc `+`*(p1, p2: Patt): Patt =
  ## Matches patthen `p1` or `p2` (ordered choice)
  new result
  if p1.len == 1 and p2.len == 1 and p1.inst[0].code == iSet and p2.inst[0].code == iSet:
    # Optimization: if both patterns are charsets, create the union set
    result.inst.add Inst(code: iSet, cs: p1.inst[0].cs + p2.inst[0].cs)
  else:
    result.inst.add Inst(code: iChoice, offset: p1.len + 2)
    result.inst.add p1.inst
    result.inst.add Inst(code: iCommit, offset: p2.len + 1)
    result.inst.add p2.inst

proc `^`*(p: Patt, count: int): Patt =
  ## Matches at least `count` repetitions of pattern `p`
  new result
  if count >= 0:
    for i in 1..count:
      result.inst.add p.inst
    result.inst.add Inst(code: iChoice, offset: p.len + 2)
    result.inst.add p.inst
    result.inst.add Inst(code: iCommit, offset: -(p.len + 1))

#
# Match VM
#

proc match(p: Patt, s: string): bool =

  var ip = 0
  var so = 0
  var stack: seq[StackFrame]
  
  proc dumpStack() =
    when debug:
      echo "  stack:"
      for i, f in stack.pairs():
        echo "    " & $i & " ip=" & $f.ip & " so=" & $f.so

  proc push(ip: int, so: int = -1) = 
    echo "  push ip:" & $ip & " so:" & $so
    stack.add StackFrame(ip: ip, so: so)
    dumpStack()

  proc pop(): StackFrame =
    doAssert stack.len > 0, "NPeg stack underrun"
    result = stack[stack.high]
    echo "  pop ip:" & $result.ip & " so:" & $result.so
    stack.del stack.high
    dumpStack()
  
  while ip < p.inst.len:
    let inst = p.inst[ip]
    var fail = false

    when debug:
      echo $ip & " | i: " & $dumpInst(inst, ip) & " | s: " & s[so..<s.len]

    case inst.code:

      of iChar:
        if so < s.len and s[so] == inst.c:
          inc ip
          inc so
        else:
          fail = true

      of iSet:
        if so < s.len and s[so] in inst.cs:
          inc ip
          inc so
        else:
          fail = true

      of iJump:
        ip += inst.offset

      of iChoice:
        push(ip + inst.offset, so)
        inc ip
      
      of iCall:
        push(ip)
        ip += inst.offset

      of iReturn:
        doAssert stack.len > 0, "NPeg stack underrun"
        let frame = pop()
        ip = frame.ip

      of iCommit:
        discard pop()
        ip += inst.offset

      of iFail:
        fail = true

      of iAny:
        if so + inst.count < s.len:
          inc ip
          inc so, inst.count
        else:
          fail = true

    if fail:
      echo "Fail"

      while stack.len > 0 and stack[stack.high].so == -1:
        stack.del stack.high

      if stack.len == 0:
        break

      let f = pop()
      ip = f.ip
      so = f.so

  when debug:
    echo "done so:" & $so & " s.len:" & $s.len & " ip:" & $ip & " p.len:" & $p.len

  result = so <= s.len and ip == p.len


when true:

  proc test(p: Patt, s: string, v: bool) =
    echo "------------ '" & s & "' -----"
    echo $p
    echo "------------"
    doAssert p.match(s) == v
    echo ""

  test(P"abc", "abc", true)
  test(P"abc", "def", false)
  test(P"abc" + P"def", "abc", true)
  test(P"abc" + P"def", "def", true)
  test(P"abc" + P"def", "boo", false)
  test(P"abc" * P"def", "a", false)
  test(P"abc" * P"def", "abc", false)
  test(P"abc" * P"def", "abcde", false)
  test(P"abc" * P"def", "abcdef", true)
  test(P"abc" * P"def", "abcdefg", true)
  test(P"ab" * P(2) * P "ef", "abcdef", true)
  test(S"abc", "a", true)
  test(S"abc", "b", true)
  test(S"abc", "d", false)
  test(S"abc" + S"ced", "a", true)
  test(S"abc" + S"def", "d", true)
  test(S"abc" + S"def", "g", false)
  test(P"abc" * S"def" * P"ghi", "abcdghi", true)
  test(P"abc" * S"def" * P"ghi", "abceghi", true)
  test(P"abc" * S"def" * P"ghi", "abcgghi", false)
  test(P"abc" * S"def" * P"ghi", "abcghi", false)
  test(P"abc"^0, "abcefg", true)
  test(P"abc"^2, "abc", false)
  test(P"abc"^2, "abcabc", true)
  test(P"abc"^2, "abcabcabc", true)
  test(R("az"), "a", true)
  test(R("az"), "b", true)
  test(R("az"), "z", true)
  test(R("az"), "A", false)

  block:
    let alpha = R("az") + R("AZ")
    let digit = R("09")
    let alphanum = alpha + digit
    let underscore = P"_"
    let identifier = (alpha + underscore) * (alphanum + underscore)^0

    test(identifier, "foo", true)
    test(identifier, "foo1", true)
    test(identifier, "1foo", false)
    test(identifier, "_foo", true)
    test(identifier, "_1foo", true)


# vi: ft=nim et ts=2 sw=2

