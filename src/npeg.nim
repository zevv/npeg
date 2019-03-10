
import strutils

type

  Opcode = enum
    iSet, iJump, iChoice, iCall, iReturn, iCommit, iPartialCommit,
    iFail, iAny, iStr, iStri, iCapStart, iCapEnd,

  Inst = object
    case code: Opcode
      of iStr, iStri:
        s: string
      of iSet:
        cs: set[char]
      of iChoice, iJump, iCall, iCommit, iPartialCommit:
        offset: int
      of iAny:
        count: int
      else:
        discard

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
    of iStr, iStri:
      result.add "\"" & inst.s & "\""
    of iSet:
      result.add "["
      for c in char.low..char.high:
        if c in inst.cs:
          result.add c
      result.add "] " & $inst.cs.card
    of iChoice, iJump, iCall, iCommit, iPartialCommit:
      result.add $(ip + inst.offset)
    of iAny:
      result.add $inst.count
    else:
      discard

proc `$`*(p: Patt): string =
  for ip, inst in p:
    if ip != 0: result.add "\n"
    result.add $ip & ": " & $dumpInst(inst, ip)

proc isSet(p: Patt): bool = p.len == 1 and p[0].code == iSet 


#
# Constructors
#

proc P*(s: string): Patt =
  ## Returns a pattern that matches string `s` literally
  result.add Inst(code: iStr, s: s)

proc Pi*(s: string): Patt =
  ## Returns a pattern that matches string `s` literally, ignoring case
  result.add Inst(code: iStri, s: s)

proc P*(count: int): Patt =
  ## Returns a pattern that matches exactly `count` characters
  result.add Inst(code: iAny, count: count)

proc S*(s: string): Patt = 
  ## Returns a pattern that matches any single character that appears in the
  ## given string. (The S stands for Set.)
  ##
  ## Note that, if s is a character (that is, a string of length 1), then
  ## P(s) is equivalent to S(s) which is equivalent to R(s..s).
  ## Note also that both S("") and R() are patterns that always fail.
  var cs: set[char]
  for c in s.items:
    cs.incl c
  result.add Inst(code: iSet, cs: cs)

proc R*(ss: varargs[string]): Patt =
  ## Returns a pattern that matches any single character belonging to one of the
  ## given ranges. Each range is a string "xy" of length 2, representing all
  ## characters with code between the codes of x and y (both inclusive).
  var cs: set[char]
  for s in ss.items:
    doAssert s.len == 2
    for c in s[0]..s[1]:
      cs.incl c
  result.add Inst(code: iSet, cs: cs)


#
# Captures
#

proc C*(p: Patt): Patt =
  result.add Inst(code: iCapStart)
  result.add p
  result.add Inst(code: iCapEnd)
  

#
# Operators for building grammars
#

proc `*`*(p1, p2: Patt): Patt =
  ## Matches pattern `p1` followed by pattern `p2`
  result.add p1
  result.add p2

proc `+`*(p1, p2: Patt): Patt =
  ## Returns a pattern equivalent to an ordered choice of `p1` and `p2`. (This
  ## is denoted by `p1` / `p2` in the original PEG notation) It matches either
  ## `p1` or `p2`, with no backtracking once one of them succeeds.
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
  ## In all cases, the resulting pattern is greedy with no backtracking (also 
  ## called a possessive repetition). That is, it matches only the longest possible 
  ## sequence of matches for patt. 
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

proc match*(p: Patt, s: string, captures: var seq[string], trace = false) : bool =

  ## The matching function. It attempts to match the given pattern against the
  ## subject string.  Unlike typical pattern-matching functions, match works
  ## only in anchored mode; that is, it tries to match the pattern with a prefix
  ## of the given subject string (at position init), not with an arbitrary
  ## substring of the subject

  var
    ip = 0 # VM instruction pointer
    si = 0 # source string index
    stack: seq[StackFrame]
    capstack: seq[int]
  
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

      of iStr:
        let l = inst.s.len
        if si <= s.len - l and s[si..<si+l] == inst.s:
          inc ip
          inc si, l
        else:
          fail = true
      
      of iStri:
        let l = inst.s.len
        if si <= s.len - l and cmpIgnoreCase(s[si..<si+l], inst.s) == 0:
          inc ip
          inc si, l
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

      of iCapStart:
        capstack.add si
        inc ip

      of iCapEnd:
        let si1 = capstack[capstack.high]
        capstack.del capstack.high
        captures.add s[si1..<si]
        inc ip

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


proc match*(p: Patt, s: string, trace: bool): bool =
  var captures: seq[string]
  match(p, s, captures, trace)



# vi: ft=nim et ts=2 sw=2

