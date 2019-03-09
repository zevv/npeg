
import strutils

type

  Opcode = enum
    iChar, iSet, iJump, iChoice, iCall, iReturn, iCommit, iPartialCommit,
    iFail, iAny

  Inst = object
    case code: Opcode
      of iChar:
        c: char
      of iSet:
        cs: set[char]
      of iChoice, iJump, iCall, iCommit, iPartialCommit:
        offset: int
      of iReturn, iFail:
        discard
      of iAny:
        count: int

  StackFrame = object
    si: int # Source index
    ip: int # Instruction pointer

  Patt* = seq[Inst]


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
    of iChoice, iJump, iCall, iCommit, iPartialCommit:
      result.add $(ip + inst.offset)
    of iReturn, iFail:
      discard
    of iAny:
      result.add $inst.count

proc `$`*(p: Patt): string =
  for ip, inst in p:
    if ip != 0: result.add "\n"
    result.add $ip & ": " & $dumpInst(inst, ip)

proc isSet(p: Patt): bool = p.len == 1 and p[0].code == iSet 


#
# Constructors
#

proc P*(s: string): Patt =
  ## Matches string `s` literally
  for c in s.items:
    result.add Inst(code: iChar, c: c)

proc P*(count: int): Patt =
  ## Matches exactly `count` characters
  result.add Inst(code: iAny, count: count)

proc S*(s: string): Patt = 
  ## Matches any character in the string `s` (Set)
  var cs: set[char]
  for c in s.items:
    cs.incl c
  result.add Inst(code: iSet, cs: cs)

proc R*(s: string): Patt =
  ## `"xy"` matches any character between x and y (Range)
  var cs: set[char]
  doAssert s.len == 2
  for c in s[0]..s[1]:
    cs.incl c
  result.add Inst(code: iSet, cs: cs)


#
# Captures
#

proc C*(p: Patt): Patt =
  p

#
# Operators for building grammars
#

proc `*`*(p1, p2: Patt): Patt =
  ## Matches pattern `p1` followed by pattern `p2`
  result.add p1
  result.add p2

proc `+`*(p1, p2: Patt): Patt =
  ## Matches patthen `p1` or `p2` (ordered choice)
  if p1.isSet and p2.isSet:
    # Optimization: if both patterns are charsets, create the union set
    result.add Inst(code: iSet, cs: p1[0].cs + p2[0].cs)
  else:
    result.add Inst(code: iChoice, offset: p1.len + 2)
    result.add p1
    result.add Inst(code: iCommit, offset: p2.len + 1)
    result.add p2

proc `^`*(p: Patt, count: int): Patt =
  ## For positive `count`, matches at least `count` repetitions of pattern `p`.
  ## For negative `count`, matches at most `count` repetitions of pattern `p`.
  if count >= 0:
    for i in 1..count:
      result.add p
    result.add Inst(code: iChoice, offset: p.len + 2)
    result.add p
    result.add Inst(code: iPartialCommit, offset: -p.len)
  else:
    result.add Inst(code: iChoice, offset: -count * (p.len + 1) + 1)
    for i in 1..(-count-1):
      result.add p
      result.add Inst(code: iPartialCommit, offset: 1)
    result.add p
    result.add Inst(code: iCommit, offset: 1)

proc `-`*(p: Patt): Patt =
  ## Returns a pattern that matches only if the input string does not match 
  ## pattern `p`. It does not consume any input, independently of success 
  ## or failure.
  result.add Inst(code: iChoice, offset: p.len + 3)
  result.add p
  result.add Inst(code: iCommit, offset: 1)
  result.add Inst(code: iFail)

proc `-`*(p1, p2: Patt): Patt =
  ## Matches pattern `p1` if pattern `p2` does not match
  if p1.isSet and p2.isSet:
    # Optimization: if both patterns are charsets, create the difference set
    result.add Inst(code: iSet, cs: p1[0].cs - p2[0].cs)
  else:
    result = -p2 * p1

#
# Match VM
#

proc match*(p: Patt, s: string, trace = false): bool =

  var ip = 0
  var si = 0
  var stack: seq[StackFrame]
  
  proc dumpStack() =
    if trace:
      echo "  stack:"
      for i, f in stack.pairs():
        echo "    " & $i & " ip=" & $f.ip & " si=" & $f.si

  proc push(ip: int, si: int = -1) = 
    if trace:
      echo "  push ip:" & $ip & " si:" & $si
    stack.add StackFrame(ip: ip, si: si)
    dumpStack()

  proc pop(): StackFrame =
    doAssert stack.len > 0, "NPeg stack underrun"
    result = stack[stack.high]
    if trace:
      echo "  pop ip:" & $result.ip & " si:" & $result.si
    stack.del stack.high
    dumpStack()

  if trace:
    echo $p
  
  while ip < p.len:
    let inst = p[ip]
    var fail = false

    if trace:
      echo "ip:" & $ip & " i:" & $dumpInst(inst, ip) & " si:" & $si & " s:" & s[si..<s.len]

    case inst.code:

      of iChar:
        if si < s.len and s[si] == inst.c:
          inc ip
          inc si
        else:
          fail = true

      of iSet:
        if si < s.len and s[si] in inst.cs:
          inc ip
          inc si
        else:
          fail = true

      of iJump:
        ip += inst.offset

      of iChoice:
        push(ip + inst.offset, si)
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

      of iPartialCommit:
        stack[stack.high].si = si
        ip += inst.offset
        dumpStack()

      of iFail:
        fail = true

      of iAny:
        if si + inst.count <= s.len:
          inc ip
          inc si, inst.count
        else:
          fail = true

    if fail:
      if trace:
        echo "Fail"

      while stack.len > 0 and stack[stack.high].si == -1:
        stack.del stack.high

      if stack.len == 0:
        break

      let f = pop()
      ip = f.ip
      si = f.si

  if trace:
    echo "done si:" & $si & " s.len:" & $s.len & " ip:" & $ip & " p.len:" & $p.len

  result = si <= s.len and ip == p.len


proc match*(s: string, p: Patt, trace = false): bool =
  match(p, s, trace)




# vi: ft=nim et ts=2 sw=2

