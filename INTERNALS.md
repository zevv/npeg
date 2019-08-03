
## Introduction

This document briefly descibes the inner workings of Npeg.

The main PEG algorithm is based on the Paper "A Text Pattern-Matching Tool
based on Parsing Expression Grammars" by Roberto Ierusalimschy, who is also the
author or LPEG. While LPEG uses a VM approach for parsing, Npeg adds an
additional step where the VM code is compiled to native Nim code which does the
parsing.

This is how Npeg works in short:

- The grammar is parsed by a Nim macro which recursively transforms this into
  a sequence of VM instructions for each grammar rule.

- The set of instructions is 'linked' into a complete program of instructions

- The linked program is translated/compiled into a state machine, implemented
  as a large Nim `case` statement that performs the parsing of the subject
  string.


## Data structures

The following data structures are used for compiling the grammar:

- `Inst`, short for "instruction": This is a object varaint which implements a
  basic VM instruction. It consists of the opcode and a number of data fields.

- `Patt`, short for "pattern": A pattern is a sequence of instructions
  `seq[Inst]` which typically match an atom from the grammar.

- `Grammar`: A grammar is collection of named patterns implemented as a
  `table[string, Patt]`. This is used as the intermediate representation of the
  complete compiled grammar and holds patterns for each of the named rules.

For captures the following data structures are relevant:

- `CapFrame`: A capframe is a frame of a specific type on the capture stack
  that points to an offset in the subject string. For each capture open and
  close pair a frame exists on the stack, thus allowing for nested captures.

- `Capture`: A capture is a completed capture that is collected and finalized
  when a capture is closed and finished. 


## Building a grammar

The first step in building a parser is the translation of the grammar into
snippets of VM instructions which match the data and perform flow control. For
details of these instructions, refer to the paper by Ierusalimschy.

The `Patt` data type is used to store a sequence of instructions. This section
describe how a pattern is built from Nim code, all of which lives in `patt.nim`
- this mechanism is later used by the macro which is parsing the actual PEG
grammar.

The basic atoms are constructed by the `newPatt()` procs. These take an
argument describing what needs to be matched in the subject, and deliver a
short sequence of instructions. For example, the `newPatt("foo")` proc
will create a pattern consisting of a single instruction: 

```
   1: line           opStr "foo"
```

There are a number of operators defined which act on one or more patterns.
These operators are used to combine multiple patterns into larger patters.

For example, the `|` operator is used for the PEG ordered choice. This takes
two patters, and results in a pattern that tries to match the first one and
then skips the second, or tries to match the second if the first fails:

```
   0: line           opChoice 3
   1: line           opStr "foo"
   2: line           opCommit 4
   3: line           opStr "bar"
   4:                opReturn
```

A number of patterns can be combined into a grammar, which is simply a table
of patterns indexed by name.


## PEG DSL to grammar

The user defines their Npeg grammar in a Nim code block, which consists of a
number of named patterns. The whole grammar is handled by the `parseGrammar()`
which iterates all individual named patterns. Each pattern is passed to the
`parsePatt()` amcro, which transforms the Nim code block AST into a Npeg
grammar. This macro recursively goes through the Nim AST and calls `newPatt()`
for building atoms, and calls the various operators acting on patterns to grow
the grammar.


## Grammar to Nim code

The `genCode()` proc is used to convert the list of instructions into Nim code
which implements the actual parser. This proc builds a `case` statement for each
VM instruction, and inserts a template for each opcode for each case.


## Example

The following grammar is specified by the user:

```
    lines <- *line                                                          
    line <- "foo" | "bar"
```

This is translated into the following VM program:

```
lines:
   0: lines          opChoice 3
   1: lines          opCall 4 line
   2: lines          opPartCommit 1
   3:                opReturn

line:
   4: line           opChoice 7
   5: line           opStr "foo"
   6: line           opCommit 8
   7: line           opStr "bar"
   8:                opReturn
```

which is then translated into the following `case` statement:

```
  while true:
    case ip
    of 0:
      opChoiceFn(3, "lines")
    of 1:
      opCallFn("line", 3, "lines")
    of 2:
      opPartCommitFn(1, "lines")
    of 3:
      opReturnFn("")
    of 4:
      opChoiceFn(7, "line")
    of 5:
      opStrFn("foo", "line")
    of 6:
      opCommitFn(8, "line")
    of 7:
      opStrFn("bar", "line")
    of 8:
      opReturnFn("")
    else:
      opFailFn()
```


