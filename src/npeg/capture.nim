
import json
import strutils
import sequtils
import npeg/[stack,common]

type

  Capture* = ref object
    case ck: CapKind
    of ckStr, ckJString, ckJBool, ckJInt, ckJFloat, ckRef, ckAction:
      s*: string
    of ckAST:
      kids: Captures
    else:
      discard
    si*: int
    name: string
    len: int

  Captures* = seq[Capture]

  FixMethod* = enum
    FixAll, FixOpen

# Convert all closed CapFrames on the capture stack to a list of Captures, all
# consumed frames are removed from the CapStack

proc fixCaptures*(s: Subject, capStack: var Stack[CapFrame], fm: FixMethod): Captures =

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
      result.add Capture(ck: c.ck, si: c.si, name: c.name)
    else:
      let i2 = stack.pop()
      assert result[i2].ck == c.ck

      if c.ck in { ckStr, ckJString, ckJBool, ckJInt, ckJFloat, ckRef, ckAction }:
        result[i2].s = if c.sPushed == "":
          s.slice(result[i2].si, c.si)
        else:
          c.sPushed
      result[i2].len = result.len - i2 - 1
  assert stack.top == 0

  # Remove closed captures from the cap stack

  capStack.top = iFrom


proc collectCaptures*(caps: Captures): Captures =
  result = caps.filterIt(it.ck == ckStr or it.ck == ckAction)


proc collectCapturesRef*(caps: Captures): Ref =
  for cap in caps:
    result.key = cap.name
    result.val = cap.s


proc collectCapturesJson*(cs: Captures): JsonNode =

  proc aux(iStart, iEnd: int, parentNode: JsonNode): JsonNode =

    var i = iStart
    while i <= iEnd:
      let cap = cs[i]

      case cap.ck:
        of ckJString: result = newJString cap.s
        of ckJBool:
          case cap.s:
            of "true": result = newJBool true
            of "false": result = newJBool false
            else: raise newException(NPegException, "Error parsing Json bool")
        of ckJInt: result = newJInt parseInt(cap.s)
        of ckJFloat: result = newJFloat parseFloat(cap.s)
        of ckJArray: result = newJArray()
        of ckJFieldDynamic: result = newJArray()
        of ckJObject: result = newJObject()
        of ckStr, ckJFieldFixed, ckAction, ckClose, ckRef, ckAST: discard
      
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


proc collectCapturesAST*(cs: Captures): ASTNode =

  proc aux(iStart, iEnd: int, parent: ASTNode, d: int=0): ASTnode =

    var i = iStart
    while i <= iEnd:
      let cap = cs[i]
      inc i
      case cap.ck:
        of ckStr:
          assert(parent != nil)
          parent.val = cap.s
        of ckAST:
          var child = ASTNode(id: cap.name)
          discard aux(i, i+cap.len-1, child, d+1)
          if parent != nil:
            parent.kids.add(child)
          else:
            result = child
          i += cap.len 
        else: discard

  result = aux(0, cs.len-1, nil)


proc `[]`*(cs: Captures, i: int): Capture =
  if i >= cs.len:
    let msg = "Capture out of range, " & $i & " is not in [0.." & $cs.high & "]"
    raise newException(NPegException, msg)
  cs[i]

