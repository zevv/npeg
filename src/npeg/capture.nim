
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


# Convert all closed CapFrames on the capture stack to a list
# of Captures

proc fixCaptures(capStack: var Stack[CapFrame], onlyOpen: bool): seq[Capture] =

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

  var stack: Stack[int]
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

  when false:
    for i, c in result:
      echo i, " ", c



proc collectCaptures*(s: string, onlyOpen: bool, capStack: var Stack[CapFrame], res: var MatchResult) =

  let cs = fixCaptures(capStack, onlyOpen)

  proc aux(iStart, iEnd: int, parentNode: JsonNode, res: var MatchResult): JsonNode =

    var i = iStart
    while i <= iEnd:
      let cap = cs[i]

      case cap.ck:
        of ckStr: res.captures.add s[cap.si1 ..< cap.si2]
        of ckJString: result = newJString s[cap.si1 ..< cap.si2]
        of ckJInt: result = newJInt parseInt(s[cap.si1 ..< cap.si2])
        of ckJFloat: result = newJFloat parseFloat(s[cap.si1 ..< cap.si2])
        of ckJArray: result = newJArray()
        of ckJFieldDynamic: result = newJArray()
        of ckJObject: result = newJObject()
        of ckJFieldFixed, ckAction, ckClose: discard
      
      let nextParentNode = 
        if result != nil and result.kind in { JArray, JObject }: result
        else: parentNode

      if parentNode != nil and parentNode.kind == JArray:
        parentNode.add result

      inc i
      let childNode = aux(i, i+cap.len-1, nextParentNode, res)

      if parentNode != nil and parentNode.kind == JObject:
        if cap.ck == ckJFieldFixed:
          parentNode[cap.name] = childNode
        if cap.ck == ckJFieldDynamic:
          let tag = result[0].getStr()
          parentNode[tag] = result[1]
          result = nil

      i += cap.len 

  res.capturesJson = aux(0, cs.len-1, nil, res)

