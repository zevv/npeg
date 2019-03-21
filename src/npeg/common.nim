
import json

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

