# Package

version       = "0.6.0"
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
