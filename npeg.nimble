# Package

version       = "0.17.1"
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
  exec "nim c -d:mingw tests/tests.nim && wine tests/tests.exe"

task test32, "32 bit tests":
  exec "nim c --cpu:i386 --passC:-m32 --passL:-m32 tests/tests.nim && tests/tests"

task testall, "Test all":
  exec "nimble test && nimble testjs && nimble testwin"
