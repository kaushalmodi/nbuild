# Time-stamp: <2018-05-17 11:04:11 kmodi>
# Generic build script

# It would be simple to just do:
#
#   import os, strformat, terminal
#
# Note that ospaths gets imported implicitly in this case.
# But I am still doing the below here so that so that I realize the number of
# procs that I am using, and also where they come from.
from os import paramCount, commandLineParams, sleep, fileExists, dirExists, createDir, execShellCmd
from ospaths import getEnv, putEnv, `/`, splitPath
from strformat import fmt
from terminal import cursorUp, eraseLine
# import os, strformat, terminal # Concise way to do the above

# Custom exception: https://forum.nim-lang.org/t/2863/1#17817
type
  ShellCmdError* = object of Exception

const
  stowPkgsRootEnvVar = "STOW_PKGS_ROOT"
  stowPkgsTargetEnvVar = "STOW_PKGS_TARGET"

var
  stowPkgsRoot: string
  stowPkgsTarget: string
  installDir: string

template execShellCmdSafe(cmd: string) =
  var exitStatus = execShellCmd(cmd)
  if exitStatus > 0:
    raise newException(ShellCmdError, "Failed to execute " & cmd)

proc setVars(pkg: string, versionDir: string, debug: bool) =
  stowPkgsRoot = getEnv(stowPkgsRootEnvVar)
  if stowPkgsRoot == "":
    raise newException(OSError, "Env variable " & stowPkgsRootEnvVar & " is not set")
  if (not dirExists(stowPkgsRoot)):
    raise newException(OSError, stowPkgsRootEnvVar & " directory `" & stowPkgsRoot & "' does not exist")
  installDir = stowPkgsRoot / pkg / versionDir
  if debug: echo "install dir = " & installDir

  if pkg == "tmux":
    stowPkgsTarget = getEnv(stowPkgsTargetEnvVar)
    if stowPkgsTarget == "":
      raise newException(OSError, "Env variable " & stowPkgsTargetEnvVar & " is not set")

proc gitOps(rev: string, revBase: string, debug: bool) =
  ## Git fetch, checkout and hard reset
  if debug: echo "git ops"
  execShellCmdSafe("git fetch --all")
  execShellCmdSafe(fmt"git checkout {revBase}")
  execShellCmdSafe("git fetch --all")
  execShellCmdSafe(fmt"git reset --hard {rev}")

# https://rosettacode.org/wiki/Handle_a_signal#Nim
# Wed May 16 18:28:02 EDT 2018 - kmodi - What does {.noconv.} do?
proc ctrlCHandler() {.noconv.} =
  echo " .. Installation canceled"
  quit 0

proc wait(limit: int=5, debug: bool) =
  ## Wait countdown

  for cnt in 0 ..< limit:
    echo fmt"Waiting for {limit-cnt} second(s) .. Press Ctrl+C to cancel this installation."
    sleep(1000)                 #1 second
    if cnt < limit:
      cursorUp(stdout); eraseLine(stdout) #similar to printf"\\r" in bash

proc make(pkg: string, debug: bool) =
  ## Make
  if debug: echo "make"
  if fileExists("."/"Makefile"): #https://devdocs.io/nim/ospaths#/,string,string
    execShellCmdSafe("make clean")
  echo "Running autogen.sh .."
  execShellCmdSafe("."/"autogen.sh")

  # Wed May 16 22:49:48 EDT 2018 - kmodi
  # TODO: Get pkg-specific configure values from a separate config file,
  # preferably TOML.
  if pkg == "tmux":
    if (not dirExists(stowPkgsTarget)):
      raise newException(OSError, stowPkgsTargetEnvVar & " directory `" & stowPkgsTarget & "' does not exist")
    putEnv("CFLAGS", fmt"-fgnu89-inline -I{stowPkgsTarget}/include -I{stowPkgsTarget}/include/ncursesw")
    putEnv("LDFLAGS", fmt"-L{stowPkgsTarget}/lib")

  execShellCmdSafe("."/"configure --prefix=" & installDir)
  execShellCmdSafe("make")

proc makeInstall(pkg: string, debug: bool) =
  ## Make install
  echo fmt"Installing {pkg} at {installDir} .."
  createDir(installDir)
  execShellCmdSafe("make install")

proc cleanup(debug: bool) =
  ## Cleanup
  if debug: echo "cleanup"
  execShellCmdSafe("make clean")

proc nbuild(pkg: string
            , rev: string="origin/master"
            , gitSkip: bool=false
            , waitSkip: bool=false
            , installSkip: bool=false
            , keep: bool=false
            , debug: bool=false) =
  ##NBuild: General purpose build script
  let revBase = rev.splitPath[1] #similar to basename in bash
  if debug: echo "rev = ", rev
  if debug: echo "revBase = ", revBase

  # https://rosettacode.org/wiki/Handle_a_signal#Nim
  setControlCHook(ctrlCHandler)

  try:
    setVars(pkg, revBase, debug)
    if (not gitSkip):
      gitOps(rev, revBase, debug)
    if (not waitSkip):
      wait(debug=debug)
    make(pkg, debug)
    if (not installSkip):
      makeInstall(pkg, debug)
      if (not keep):
        cleanup(debug)
    echo "Done!"
  except ShellCmdError:
    echo "Shell command error: " & getCurrentExceptionMsg()
  except:
    echo "Error happened: " & getCurrentExceptionMsg()

when isMainModule:
  import cligen
  dispatch(nbuild,
           help = {"pkg" : "Name of the package being installed\nExamples: 'nim', 'emacs', 'tmux'"
                    , "rev" : "Revision (git remote branch or tag) of the package begin installed\nExamples: 'origin/devel', '2.7'"
                    , "gitSkip" : "Skip all git operations in the beginning: fetching and hard reset"
                    , "waitSkip" : "Skip the countdown before the start of build"
                    , "installSkip" : "Skip the installation of the package after the build step"
                    , "keep" : "Keep the built files in the current directory after the installation step"
                    , "debug" : "Enable printing statements useful for debug"
                  },
           short = {"gitSkip" : 'G'
                     , "waitSkip" : 'W'
                     , "installSkip" : 'I'
                     , "debug" : 'D'
                     })
