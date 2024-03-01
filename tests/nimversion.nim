
import strutils
import npeg

type
  NimType = enum Nim, NimSkull

  Version = object
    maj, min, rev: int
    extra: string

  NimVersion = object
    typ: NimType
    version: Version
    os: string
    cpu: string
    date: string
    git: string
    boot_switches: seq[string]


let p = peg("nimversion", nv: NimVersion):

  S <- *{' ','\t','\n','\r'}
  nimversion <- oldnim_version | nimskull_version

  oldnim_version <- header * S *
                    "Compiled at " * date * S *
                    "Copyright (c) 2006-2024 by Andreas Rumpf" * S *
                    "git hash:" * S * git * S * 
                    "active boot switches:" * S * boot_switches

  nimskull_version <- header * S *
                      "Source hash: " * git * S *
                      "Source date: " * date

  header <- typ * S * "Compiler Version" * S * version * S * "[" * os * ":" * S * cpu * "]" * S

  typ <- typ_nimskull | typ_nim
  typ_nim <- "Nim": nv.typ = NimType.Nim
  typ_nimskull <- "Nimskull": nv.typ = NimType.NimSkull

  int <- +{'0'..'9'}
  os <- >+Alnum: nv.os = $1
  cpu <- >+Alnum: nv.cpu = $1
  git <- >+{'0'..'9','a'..'f'}: nv.git = $1
  boot_switches <- *(boot_switch * S)
  boot_switch <- >+Graph: nv.boot_switches.add($1)
  date <- >+{'0'..'9','-'}: nv.date = $1
  version <- >int * "." * >int * "." * >int * ?"-" * >*Graph:
    nv.version.maj = parseInt($1)
    nv.version.min = parseInt($2)
    nv.version.rev = parseInt($3)
    nv.version.extra = $4


let vnim = """Nim Compiler Version 2.1.1 [Linux: amd64]
Compiled at 2024-03-01
Copyright (c) 2006-2024 by Andreas Rumpf

git hash: 1e7ca2dc789eafccdb44304f7e42206c3702fc13
active boot switches: -d:release -d:danger
"""

let vskull = """Nimskull Compiler Version 0.1.0-dev.21234 [linux: amd64]

Source hash: 4948ae809f7d84ef6d765111a7cd0c7cf2ae77d2
Source date: 2024-02-18
"""

var nv: NimVersion

block:
  let r = p.match(vnim, nv)
  if r.ok:
    echo nv.repr

block:
  let r = p.match(vskull, nv)
  if r.ok:
    echo nv.repr

