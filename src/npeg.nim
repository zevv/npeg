
import strutils

type

  Opcode = enum
    iChar, iSet, iJump, iChoice, iCall, iReturn, iCommit, iPartialCommit, iFail, iAny

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
    so: int # Source offset
    ip: int # Instruction pointer

  Patt* = object
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
    of iChoice, iJump, iCall, iCommit, iPartialCommit:
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

proc isSet(p: Patt): bool = p.len == 1 and p.inst[0].code == iSet 

#
# Constructors
#

proc P*(s: string): Patt =
  ## Matches string `s` literally
  for c in s.items:
    result.inst.add Inst(code: iChar, c: c)

proc P*(count: int): Patt =
  ## Matches exactly `count` characters
  result.inst.add Inst(code: iAny, count: count)

proc S*(s: string): Patt = 
  ## Matches any character in the string `s` (Set)
  var cs: set[char]
  for c in s.items:
    cs.incl c
  result.inst.add Inst(code: iSet, cs: cs)

proc R*(s: string): Patt =
  ## `"xy"` matches any character between x and y (Range)
  var cs: set[char]
  doAssert s.len == 2
  for c in s[0]..s[1]:
    cs.incl c
  result.inst.add Inst(code: iSet, cs: cs)


#
# Operators for building grammars
#

proc `*`*(p1, p2: Patt): Patt =
  ## Matches pattern `p1` followed by pattern `p2`
  result.inst.add p1.inst
  result.inst.add p2.inst

proc `+`*(p1, p2: Patt): Patt =
  ## Matches patthen `p1` or `p2` (ordered choice)
  if p1.isSet and p2.isSet:
    # Optimization: if both patterns are charsets, create the union set
    result.inst.add Inst(code: iSet, cs: p1.inst[0].cs + p2.inst[0].cs)
  else:
    result.inst.add Inst(code: iChoice, offset: p1.len + 2)
    result.inst.add p1.inst
    result.inst.add Inst(code: iCommit, offset: p2.len + 1)
    result.inst.add p2.inst

proc `^`*(p: Patt, count: int): Patt =
  ## For positive `count`, matches at least `count` repetitions of pattern `p`.
  ## For negative `count`, matches at most `count` repetitions of pattern `p`.
  if count >= 0:
    for i in 1..count:
      result.inst.add p.inst
    result.inst.add Inst(code: iChoice, offset: p.len + 2)
    result.inst.add p.inst
    result.inst.add Inst(code: iPartialCommit, offset: -p.len)
  else:
    result.inst.add Inst(code: iChoice, offset: -count * (p.len + 1) + 1)
    for i in 1..(-count-1):
      result.inst.add p.inst
      result.inst.add Inst(code: iPartialCommit, offset: 1)
    result.inst.add p.inst
    result.inst.add Inst(code: iCommit, offset: 1)

#
# Match VM
#

proc match*(p: Patt, s: string, trace = false): bool =

  var ip = 0
  var so = 0
  var stack: seq[StackFrame]
  
  proc dumpStack() =
    if trace:
      echo "  stack:"
      for i, f in stack.pairs():
        echo "    " & $i & " ip=" & $f.ip & " so=" & $f.so

  proc push(ip: int, so: int = -1) = 
    if trace:
      echo "  push ip:" & $ip & " so:" & $so
    stack.add StackFrame(ip: ip, so: so)
    dumpStack()

  proc pop(): StackFrame =
    doAssert stack.len > 0, "NPeg stack underrun"
    result = stack[stack.high]
    if trace:
      echo "  pop ip:" & $result.ip & " so:" & $result.so
    stack.del stack.high
    dumpStack()
  
  while ip < p.inst.len:
    let inst = p.inst[ip]
    var fail = false

    if trace:
      echo "ip:" & $ip & " | i:" & $dumpInst(inst, ip) & " | so:" & $so & " | s:" & s[so..<s.len]

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

      of iPartialCommit:
        stack[stack.high].so = so
        ip += inst.offset
        dumpStack()

      of iFail:
        fail = true

      of iAny:
        if so + inst.count < s.len:
          inc ip
          inc so, inst.count
        else:
          fail = true

    if fail:
      if trace:
        echo "Fail"

      while stack.len > 0 and stack[stack.high].so == -1:
        stack.del stack.high

      if stack.len == 0:
        break

      let f = pop()
      ip = f.ip
      so = f.so

  if trace:
    echo "done so:" & $so & " s.len:" & $s.len & " ip:" & $ip & " p.len:" & $p.len

  result = so <= s.len and ip == p.len





# vi: ft=nim et ts=2 sw=2

