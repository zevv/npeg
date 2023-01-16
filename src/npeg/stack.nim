
# This module implements a basic stack[T]. This is used instead of seq[T]
# because the latter has bad performance when unwinding more then one frame at
# a time (ie, setlen). These stacks keep track of their own top and do not
# shrink the underlying seq when popping or unwinding.

type
  Stack*[T] = object
    name: string
    top*: int
    max: int
    frames: seq[T]


proc `$`*[T](s: Stack[T]): string =
  for i in 0..<s.top:
    result.add $i & ": " & $s.frames[i] & "\n"

proc initStack*[T](name: string, len: int, max: int=int.high): Stack[T] =
  result.name = name
  result.frames.setLen len
  result.max = max

proc grow*[T](s: var Stack[T]) =
  if s.top >= s.max:
    mixin NPegStackOverflowError
    raise newException(NPegStackOverflowError, s.name & " stack overflow, depth>" & $s.max)
  s.frames.setLen s.frames.len * 2

template push*[T](s: var Stack[T], frame: T) =
  if s.top >= s.frames.len: grow(s)
  s.frames[s.top] = frame
  inc s.top

template pop*[T](s: var Stack[T]): T =
  assert s.top > 0
  dec s.top
  s.frames[s.top]

template peek*[T](s: Stack[T]): T =
  assert s.top > 0
  s.frames[s.top-1]

template `[]`*[T](s: Stack[T], idx: int): T =
  assert idx < s.top
  s.frames[idx]

template update*[T](s: Stack[T], field: untyped, val: untyped) =
  assert s.top > 0
  s.frames[s.top-1].field = val

