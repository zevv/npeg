
import strutils
import sequtils
import npeg/[stack,common]

type

  Capture*[S] = ref object
    case ck: CapKind
    of ckStr, ckRef, ckAction:
      when S is char:
        s*: string
      else:
        s*: S
    else:
      discard
    si*: int
    name: string
    len: int

  Captures*[S] = seq[Capture[S]]

  FixMethod* = enum
    FixAll, FixOpen

# Convert all closed CapFrames on the capture stack to a list of Captures, all
# consumed frames are removed from the CapStack

proc fixCaptures*[S](s: openArray[S], capStack: var Stack[CapFrame[S]], fm: FixMethod): Captures[S] =

  assert capStack.top > 0
  assert capStack.peek.cft == cftCLose
  when npegDebug:
    echo $capStack

  # Search the capStack for cftOpen matching the cftClose on top

  var iFrom = 0

  if fm == FixOpen:
    var i = capStack.top - 1
    var depth = 0
    while true:
      if capStack[i].cft == cftClose: inc depth else: dec depth
      if depth == 0: break
      dec i
    iFrom = i

  # Convert the closed frames to a seq[Capture]

  var stack = initStack[int]("captures", 8)
  for i in iFrom..<capStack.top:
    let c = capStack[i]
    if c.cft == cftOpen:
      stack.push result.len
      result.add Capture[S](ck: c.ck, si: c.si, name: c.name)
    else:
      let i2 = stack.pop()
      assert result[i2].ck == c.ck

      if c.ck in { ckStr, ckRef, ckAction }:
        when S is char:
          result[i2].s = if c.sPushed == "":
            s.slice(result[i2].si, c.si)
          else:
            c.sPushed
        else:
          result[i2].s = s[result[i2].si]
      result[i2].len = result.len - i2 - 1
  assert stack.top == 0

  # Remove closed captures from the cap stack

  capStack.top = iFrom


proc collectCaptures*[S](caps: Captures[S]): Captures[S] =
  result = caps.filterIt(it.ck == ckStr or it.ck == ckAction)


proc collectCapturesRef*(caps: Captures): Ref =
  for cap in caps:
    result.key = cap.name
    result.val = cap.s


#proc `[]`*[S](cs: Captures[S], i: int): Capture[S] =
#  if i >= cs.len:
#    let msg = "Capture out of range, " & $i & " is not in [0.." & $cs.high & "]"
#    raise newException(NPegException, msg)
#  cs[i]

