
import json
import strutils
import stack
import common

type

  Capture* = object
    ck: CapKind
    si1, si2: int
    name: string
    len: int

  Captures* = seq[Capture]


# Convert all closed CapFrames on the capture stack to a list
# of Captures, all consumed frames are removed from the CapStack

proc fixCaptures*(capStack: var Stack[CapFrame], onlyOpen: bool): Captures =

  assert capStack.top > 0
  assert capStack.peek.cft == cftCLose

  # Search the capStack for cftOpen matching the cftClose on top

  var iFrom = 0

  if onlyOpen:
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
      result.add Capture(ck: c.ck, si1: c.si, name: c.name)
    else:
      let i2 = stack.pop()
      result[i2].si2 = c.si
      result[i2].len = result.len - i2 - 1
  assert stack.top == 0

  # Remove closed captures from the cap stack

  capStack.top = iFrom


proc collectCaptures*(s: string, cs: Captures): seq[string] =
  for c in cs:
    if c.ck == ckStr:
      result.add s[c.si1 ..< c.si2]


proc collectCapturesJson*(s: string, cs: Captures): JsonNode =

  proc aux(iStart, iEnd: int, parentNode: JsonNode): JsonNode =

    var i = iStart
    while i <= iEnd:
      let cap = cs[i]

      case cap.ck:
        of ckJString: result = newJString s[cap.si1 ..< cap.si2]
        of ckJInt: result = newJInt parseInt(s[cap.si1 ..< cap.si2])
        of ckJFloat: result = newJFloat parseFloat(s[cap.si1 ..< cap.si2])
        of ckJArray: result = newJArray()
        of ckJFieldDynamic: result = newJArray()
        of ckJObject: result = newJObject()
        of ckStr, ckJFieldFixed, ckAction, ckClose: discard
      
      let nextParentNode = 
        if result != nil and result.kind in { JArray, JObject }: result
        else: parentNode

      if parentNode != nil and parentNode.kind == JArray:
        parentNode.add result

      inc i
      let childNode = aux(i, i+cap.len-1, nextParentNode)

      if parentNode != nil and parentNode.kind == JObject:
        if cap.ck == ckJFieldFixed:
          parentNode[cap.name] = childNode
        if cap.ck == ckJFieldDynamic:
          let tag = result[0].getStr()
          parentNode[tag] = result[1]
          result = nil

      i += cap.len 

  result = aux(0, cs.len-1, nil)
  if result == nil:
    result = newJNull()

