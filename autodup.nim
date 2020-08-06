import os, osproc, strutils, tables, times

import cligen, regex, weave

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

  Process = tuple[path, value: string]

var
  HashMap: Table[string, string]
  chProcess: Channel[Process]
  chRecurse: Channel[bool]
chProcess.open()
chRecurse.open()

# Actions

proc moveaction(path, dupdir: string) =
  let dest = dupdir / tailDir(path)

  try:
    createDir(parentDir(dest))
    moveFile(path, dest)
  except:
    echo "Already exists " & dest

proc removeaction(path: string, kind: PathComponent) =
  if kind == pcFile:
    if not tryRemoveFile(path):
      echo "Failed to remove " & path
  elif kind == pcDir:
    try:
      removeDir(path)
    except:
      echo "Failed to remove dir " & path

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
    echo outp

# Checks

proc getHash(state: State, path: string) =
  let
    outp = execCmdEx("openssl sha512 " & path).output
    hash = outp[outp.find(' ') .. ^2]
  chProcess.send((path, hash))

proc getFingerprint(state: State, path: string) =
  discard

proc getEmpty(state: State, path: string) =
  discard

# Filter

proc recurse(state: State, source: string) =
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

  syncScope():
    for path in walkDirRec(source, yieldFilter = {filter}):
      # count += 1

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

      if state.duplicate:
        spawn state.getHash(path)
      elif state.music:
        spawn state.getFingerprint(path)
      elif state.empty:
        spawn state.getEmpty(path)

  chRecurse.send(true)

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

  syncScope():
    var done = 0
    for source in sources:
      spawn state.recurse(source)

    while true:
      # Break on done
      let (rdy, msg) = chRecurse.tryRecv()
      if rdy: done.inc()
      if done == sources.len: break

      let (todo, process) = chProcess.tryRecv()
      if todo:
        if HashMap.hasKey(process[1]):
          #echo process[0] & " is a dup of " & HashMap[process[1]]
          state.action(process[0], HashMap[process[1]])
        else:
          HashMap[process[1]] = process[0]

when isMainModule:
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
  exit(Weave)