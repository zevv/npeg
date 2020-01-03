
import strutils
import sequtils
import npeg/[stack,common]

type

  Capture*[S] = ref object
    ck: CapKind
    si*: int
    name: string
    len: int
    when S is char:
      s*: string
    else:
      s*: S

  Captures*[S] = ref object
    capList*: seq[Capture[S]]

  FixMethod* = enum
    FixAll, FixOpen

# Convert all closed CapFrames on the capture stack to a list of Captures, all
# consumed frames are removed from the CapStack

proc fixCaptures*[S](s: openArray[S], capStack: var Stack[CapFrame[S]], fm: FixMethod): Captures[S] =

  new result
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
      stack.push result.capList.len
      result.capList.add Capture[S](ck: c.ck, si: c.si, name: c.name)
    else:
      let i2 = stack.pop()
      assert result[i2].ck == c.ck
      result[i2].s = if c.ck == ckPushed:
        c.sPushed
      else:
        s.slice(result[i2].si, c.si)
      result[i2].len = result.capList.len - i2 - 1
  assert stack.top == 0

  # Remove closed captures from the cap stack

  capStack.top = iFrom


proc collectCaptures*[S](caps: Captures[S]): Captures[S] =
  result = Captures[S](
    capList: caps.capList.filterIt(it.ck in {ckStr, ckPushed, ckAction})
  )

proc collectCapturesRef*(caps: Captures): Ref =
  for cap in caps.capList:
    result.key = cap.name
    result.val = cap.s

proc `[]`*[S](cs: Captures[S], i: int): Capture[S] =
  if i >= cs.capList.len:
    let msg = "Capture out of range, " & $i & " is not in [0.." & $cs.capList.high & "]"
    raise newException(NPegException, msg)
  cs.capList[i]

iterator items*[S](captures: Captures[S]): Capture[S] =
  for c in captures.capList:
    yield c

proc len*[S](captures: Captures[S]): int =
  captures.capList.len

