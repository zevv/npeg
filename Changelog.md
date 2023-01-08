1.1.0 - 2023-01-08
==================

- Added alternate `∙` concatenation operator
- Fixed fixBareExceptionWarning in Nim devel
- Added table of contents to README.md

1.0.1 - 2022-12-10
==================

- Bugfix release, fixes "expression 'discard' has no type (or is ambiguous)" in 
  rare cases

1.0.0 - 2022-11-27
==================

- Improved stack trace handling
- Fixed matchFile() for empty files

0.27.0 - 2022-11-06
===================

- Augment the Nim stack trace with the NPeg return stack on exceptions
- Documentation updates

0.26.0 - 2021-11-27
===================

- Improved lineinfo in code blocks for better backtraces
- Some documentation improvements

0.25.0 - 2021-09-11
===================

- Omit the `.computedGoto.` in the inner parser loop for grammars with more
  then 10k instructions to work around the nim compiler limitation

0.24.1 - 2021-01-16
===================

- Added mixin for 'repr' to allow clean tracing of user types

0.24.0 - 2020-11-20
===================

- Added -d:npegGcsafe

0.23.2 - 2020-11-06
===================

- Small improvement in npeg systax checking

0.23.0 - 2020-09-23
===================

- Reinstated [] out of bound check for capturest
- Dropped profiler support, the implementation was bad
- Small documentation improvements
- Added RFC3339 date parser to libs

0.22.2 - 2019-12-27
===================

- Skip --gc:arc tests for nim <1.1 to fix Nim CI builds.

0.22.1 - 2019-12-27
===================

- Bugfix in codegen causing problems with ^1 notation in code blocks.

0.22.0 - 2019-12-24
===================

- Changed the parsing subject from `openArray[char]` to `openArray[T]` and
  added a 'literal' atom to the grammar. This allows NPeg to parse lists of
  any type, making it suitable for separate lexer and parser stages. See
  tests/lexparse.nim for a concise example.

- Added `@` syntactic sugar to access the match offset inside code block
  captures.

- Dropped Json and AST captures - no complains heard since deprecation, and it
  simplifies the code base to aid the development new features.

0.21.3 - 2019-12-06
===================

- Fixed off-by-one error in range `P[m..n]` operator, which would also match
  `P` times `n+1`

- Various documentation improvements

0.21.2 - 2019-11-26
===================

- Fixed the way dollar captures are rewritten to avoid the name space clash
  which was introduced by Nim PR #12712.

0.21.1 - 2019-11-19
===================

- Bugfix for templates generating ordered choices

0.21.0 - 2019-10-28
===================

- anonymous `patt` patterns now also take a code block

- deprecated AST and Json captures. AST captures are not flexible enough, and
  the functionality can be better implemented using code block captures and
  domain-specific AST object types. The Json captures were added in the early
  days of NPeg as a flexible way to store captures, but this does not mix well
  with custom captures and can not handle things like string unescaping. Both
  capture types were removed from the documentation and a .deprecated. pragma
  was added to the implementation. If you use Json or AST captures and think
  deprecation is a mistake, let me know.

0.20.0 - 2019-10-18
===================

- Added precedence operators - this allows constructions of Pratt parsers with
  bounded left recursion and operator precedence.
- Added run time profiler, enable with -d:npegProfile
- Performance improvements

0.19.0 - 2019-10-11
===================

- Significant performance improvements
- Changed semantincs of code block captures: $0 now always captures the
  total subject captured in a rule. This is a minor API change that only
  affects code using the `capture[]` notation inside code blocks
- Added fail() function to force a parser fail in a code block capture
- Added push() function to allow code block captures to push captures
  back on the stack
- Check for loops caused by repeat of empty strings at compile time

0.18.0 - 2019-09-26
===================

- Runtime performance improvements

0.17.1 - 2019-09-19
===================

- Bugfix release (removed lingering debug echo)

0.17.0 - 2019-09-17
===================

- Various runtime and compiletime performance improvements

0.16.0 - 2019-09-08
===================

- Templates can now also be used in libraries
- Added railroad diagram generation with -d:npegGraph
- Improved error reporting

0.15.0 - 2019-08-31
===================

- Generic parser API changed: the peg() macro now explicity passes the
  userdata type and identifier.

0.14.1 - 2019-08-28
===================

- Added templates / parameterised rules
- Added custom match validation in code block capture
- Added basic types, utf8 and uri libs
- Added global pattern library support
- Proc matchFile() now uses memfiles/mmap for zero copy parsers
- Implemented method to pass user variable to code block captures
- Added AST capture type for building simple abstract syntax trees
- Added Jb() capture for Json booleans

0.13.0 - 2019-07-21
===================

- The capture[] variable available inside code block matches now allows access
  to the match offset as well. This is an API change since the type of capture
  changed from seq[string] to seq[Capture].

0.12.0 - 2019-07-14
===================

- Documentation updates
- Made some error bounds compile-time configurable
- Fix for more strict Nim compiler checks

0.11.0 - 2019-05-29
===================

- Added support for named backreferences
- Added safeguards to prevent grammars growing out of bounds
- Added Graphviz .dot debugging output for parser debugging
- Added `matchLen` and `matchMax` fields to `NPegException`
- Improved pattern syntax error messages

0.10.0 - 2019-04-24
===================

- Fixed 'Graph' character class

0.9.0 - 2019-03-31
==================

- Some syntax changes to fix compilation with mainline Nim 0.19.4

0.8.0 - 2019-03-30
==================

- Added syntactic sugar for accessing the captures[] seq in capture
  code blocks with dollar-number variables $1..$9

0.7.0 - 2019-03-29
==================

- Action callbacks (%) dropped in favour of Nim code block callbacks.

0.6.0 - 2019-03-27
==================

- API change: count syntax changed from {n} to [n].

- Optimizations in code generation

0.5.0 - 2019-03-27
==================

- API change: peg() and patt() now return an object of type Parser
  instead of a proc, and the function match(p: Parser) is now used for
  matching the subject. match() can match string and cstring types, 
  matchFile() matches a file using memFile.

- Added builtin atoms Upper, Lower, Digit, HexDigit, Alpha

- Added `@` search operator

- Added `&` and predicate

0.4.0 - 2019-03-24
==================

- Improved tracing output, during trace the originating rule name
  for each instruction is dumped.

- Optimizations
