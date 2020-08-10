import os, strutils, tables, terminal, times

import cligen, meow, regex

when defined(weave):
  import weave
else:
  import macros, threadpool

  macro syncScope(body: untyped): untyped =
    result = body

template ercho(str: untyped) =
  stdout.eraseLine()
  stdout.write(str)
  stdout.flushFile()

type
  State = ref object
    duplicate, empty, music: bool
    kind: PathComponent

    pattern, regex: string
    patternfull, regexfull: string
    cregex, cregexfull: Regex
    greater, lesser: int
    after, before: int

    move: string
    delete: bool
    invert: string
    quiet: bool

  Process = ref object
    path: string
    size: BiggestInt
    value: string

  First = ref object
    path: string
    hashed: bool

var
  SizeMap {.threadvar.}: Table[BiggestInt, First]
  HashMap: Table[string, string]
  chProcess: Channel[Process]
  chRecurse: Channel[int]
chProcess.open()
chRecurse.open()

# Actions

proc moveaction(path, dupdir: string) =
  let dest = dupdir / tailDir(path)

  try:
    createDir(parentDir(dest))
    moveFile(path, dest)
  except:
    ercho "Already exists " & dest

proc removeaction(path: string, kind: PathComponent) =
  if kind == pcFile:
    if not tryRemoveFile(path):
      ercho "Failed to remove " & path
  elif kind == pcDir:
    try:
      removeDir(path)
    except:
      ercho "Failed to remove dir " & path

proc action(state: State, path: string, orig = "") =
  var
    action = ""
  if state.move.len != 0:
    spawn moveaction(path, state.move)
    action = "Moving "
  elif state.delete:
    spawn removeaction(path, state.kind)
    action = "Removing "
  else:
    action = "Found "

  if not state.quiet:
    var outp = action & path
    if orig != "":
      outp &= " == " & orig
    ercho outp & "\n"

# Checks

proc getHash(state: State, path: string, size: BiggestInt) =
  ercho "Hashing " & path
  let process =
    Process(path: path, size: size, value: $MeowFile(path))
  chProcess.send(process)

proc getFingerprint(state: State, path: string, size: BiggestInt) =
  discard

proc getEmpty(state: State, path: string) =
  discard

# Filter

proc recurse(state: State, sources: seq[string]) =
  let
    now = getTime()
    after = now - initTimeInterval(days=state.after)
    before = now - initTimeInterval(days=state.before)

  var
    filter =
      if state.duplicate or state.music:
        pcFile
      elif state.empty:
        pcDir
      else:
        raise newException(Exception, "Error")

  template checkCondition(condition, flag: untyped) =
    if not condition and flag notin state.invert:
      continue
    elif condition and flag in state.invert:
      continue

  template processPath(path, size: untyped) =
    ercho "Checking " & path
    processed.inc()
    if state.duplicate:
      spawn state.getHash(path, size)
    elif state.music:
      spawn state.getFingerprint(path, size)
    elif state.empty:
      spawn state.getEmpty(path)

  var
    total = 0
    processed = 0
  syncScope():
    for source in sources:
      for path in walkDirRec(source, yieldFilter = {filter}):
        let
          fname = path.extractFilename()
          info = path.getFileInfo()

        if state.pattern.len != 0:
          # Pattern check
          checkCondition fname.contains(state.pattern), 'p'

        if state.patternfull.len != 0:
          # Pattern check
          checkCondition path.contains(state.patternfull), 'P'

        if state.regex.len != 0:
          # Regex check
          checkCondition fname.contains(state.cregex), 'r'

        if state.regexfull.len != 0:
          # Regex check
          checkCondition path.contains(state.cregexfull), 'R'

        if state.greater != 0:
          # Size check
          checkCondition info.size > state.greater, 'g'

        if state.lesser != 0:
          # Size check
          checkCondition info.size < state.lesser, 'l'

        if state.after != 0:
          # Date check
          checkCondition info.lastWriteTime > after, 'a'

        if state.before != 0:
          # Date check
          checkCondition info.lastWriteTime < before, 'b'

        total.inc()
        if not SizeMap.hasKey(info.size):
          # First of size, hash later
          SizeMap[info.size] = First(path: path)
          continue
        else:
          if not SizeMap[info.size].hashed:
            # Second of size, hash first
            processPath(SizeMap[info.size].path, info.size)
            SizeMap[info.size].hashed = true

        processPath(path, info.size)

  chRecurse.send(total)
  chRecurse.send(processed)

proc main(
  duplicate = false, empty = false, music = false,

  pattern = "", regex = "",
  patternfull = "", regexfull = "",
  greater = 0, lesser = 0,
  after = 0, before = 0,

  move = "",
  delete = false,

  invert = "",
  quiet = false,

  sources: seq[string]
) =
  let
    state = new(State)
  state.duplicate = duplicate
  state.empty = empty
  state.music = music

  state.pattern = pattern
  state.patternfull = patternfull
  state.regex = regex
  if state.regex.len != 0:
    state.cregex = re(regex)
  state.regexfull = regexfull
  if state.regexfull.len != 0:
    state.cregexfull = re(regexfull)
  state.greater = greater
  state.lesser = lesser
  state.after = after
  state.before = before

  state.move = move
  state.delete = delete

  state.invert = invert
  state.quiet = quiet

  if not (state.duplicate or state.empty or state.music):
    echo "No search action selected"
    quit(1)
  elif sources.len == 0:
    echo "No source directories selected"
    quit(1)

  if state.move.len != 0:
    createDir(state.move)
  if state.duplicate or state.music:
    state.kind = pcFile
  elif state.empty:
    state.kind = pcDir

  var
    received = 0
    matches = 0
    total = -1
    processed = -1
    size: BiggestInt = 0
  syncScope():
    spawn state.recurse(sources)

    while true:
      # Break on done
      if total == -1:
        let (rdy, val) = chRecurse.tryRecv()
        if rdy: total = val
      elif processed == -1:
        let (rdy, val) = chRecurse.tryRecv()
        if rdy: processed = val
      elif processed == received:
        break

      let (todo, process) = chProcess.tryRecv()
      if todo:
        received.inc()
        if HashMap.hasKey(process.value):
          state.action(process.path, HashMap[process.value])
          matches.inc()
          size += process.size
        else:
          HashMap[process.value] = process.path

  when not defined(weave):
    sync()

  if state.duplicate:
    ercho "Hashed " & $received & " / " & $total & " files, " &
      $matches & " duplicate(s) found (" &
      formatFloat(float(size)/1024/1024, ffDecimal, 2) & " MB)"

when isMainModule:
  when defined(weave):
    init(Weave)
  dispatch(main,
    help = {
      "duplicate": "search for duplicate files",
      "empty": "search for empty directories",
      "music": "search for duplicate music files",

      "pattern": "include those containing pattern in filename",
      "patternfull": "include those containing pattern in path",
      "regex": "include those containing regex in fileame",
      "regexfull": "include those containing regex in path",
      "greater": "include size greater than (bytes)",
      "lesser": "include size lesser than (bytes)",
      "after": "include last modified after (days)",
      "before": "include last modified before (days)",

      "move": "move results to",
      "delete": "delete results",
      "invert": "invert specified flags",
      "quiet": "quiet - do not display results",

      "sources": "directories to search"
    },
    short = {
      "duplicate": 'D', "empty": 'E', "music": 'M',

      "pattern": 'p', "regex": 'r',
      "patternfull": 'P', "regexfull": 'R',
      "greater": 'g',
      "lesser": 'l',
      "after": 'a',
      "before": 'b',

      "move": 'm',
      "delete": 'x',
      "invert": 'i',
      "quiet": 'q'
    }
  )
  when defined(weave):
    exit(Weave)