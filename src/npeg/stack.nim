
type
  Stack*[T] = object
    top*: int
    frames: seq[T]


proc `$`*[T](s: Stack[T]): string =
  for i in 0..<s.top:
    result.add $i & ": " & $s.frames[i] & "\n"

template push*[T](s: var Stack[T], frame: T) =
  if s.top >= s.frames.len:
    s.frames.setLen if s.frames.len == 0: 8 else: s.frames.len * 2
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


export push

