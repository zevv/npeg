# Package

version       = "0.7.0"
author        = "Ico Doornekamp"
description   = "a PEG library"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]

# Dependencies

requires "nim >= 0.19.0"

# Test

task test, "Runs the test suite":
  exec "nim c -r tests/tests.nim"

task testjs, "Javascript tests":
  exec "nim js tests/tests.nim && node tests/tests.js"

task testwin, "Mingw tests":
  exec "nim c --gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-gcc --os:windows tests/tests.nim && wine tests/tests.exe"

task testall, "Test all":
  exec "nimble test && nimble testjs && nimble testwin"
