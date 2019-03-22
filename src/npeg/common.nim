
import json
import strutils

type

  NPegException* = object of Exception
  
  CapFrameType* = enum cftOpen, cftClose
  
  CapKind* = enum
    ckStr,          # Plain string capture
    ckJString,         # JSON string capture
    ckJInt,         # JSON Int capture
    ckJFloat,       # JSON Float capture
    ckJArray,       # JSON Array
    ckJObject,      # JSON Object
    ckJFieldFixed,  # JSON Object field with fixed tag
    ckJFieldDynamic,# JSON Object field with dynamic tag
    ckAction,       # Action capture, executes Nim code at match time
    ckClose,        # Closes capture

  CapFrame* = tuple
    cft: CapFrameType
    si: int
    ck: CapKind
    name: string

const npegTrace* = defined(npegTrace)

# Helper procs

proc subStrCmp*(s: string, si: int, s2: string): bool =
  if si > s.len - s2.len:
    return false
  for i in 0..<s2.len:
    if s[si+i] != s2[i]:
      return false
  return true

proc subIStrCmp*(s: string, si: int, s2: string): bool =
  if si > s.len - s2.len:
    return false
  for i in 0..<s2.len:
    if s[si+i].toLowerAscii != s2[i].toLowerAscii:
      return false
  return true

