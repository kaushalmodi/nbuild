# Time-stamp: <2018-05-17 08:08:05 kmodi>
# Generic build script

import os                       #for paramCount, commandLineParams, sleep, fileExists
import strformat                #for fmt
import terminal                 #for eraseLine

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

proc envVarCheck(pkg: string, debug: bool) =
  stowPkgsRoot = getEnv(stowPkgsRootEnvVar)
  if stowPkgsRoot.len == 0:
    raise newException(OSError, "Env variable " & stowPkgsRootEnvVar & " is not set")
  if pkg == "tmux":
    stowPkgsTarget = getEnv(stowPkgsTargetEnvVar)
    if stowPkgsTarget.len == 0:
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
proc waitQuitHandler() {.noconv.} =
  echo " .. Installation canceled"
  quit 0

proc wait(seconds: int=5, debug: bool) =
  ## Wait countdown
  var cnt = seconds

  # https://rosettacode.org/wiki/Handle_a_signal#Nim
  setControlCHook(waitQuitHandler)

  while cnt > 0:
    echo fmt"Waiting for {cnt} second(s) .. Press Ctrl+C to cancel this installation."
    sleep(1000)                 #1 second
    cnt = cnt - 1
    if cnt > 0:
      cursorUp(stdout); eraseLine(stdout) #similar to printf"\\r" in bash

proc setInstallDir(pkg: string, versionDir: string, debug: bool) =
  if dirExists(stowPkgsRoot):
    installDir = stowPkgsRoot / pkg / versionDir
    if debug: echo "install dir = " & installDir
  else:
    raise newException(OSError, stowPkgsRootEnvVar & " directory `" & stowPkgsRoot & "' does not exist")

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
    if dirExists(stowPkgsTarget):
      putEnv("CFLAGS", fmt"-fgnu89-inline -I{stowPkgsTarget}/include -I{stowPkgsTarget}/include/ncursesw")
      putEnv("LDFLAGS", fmt"-L{stowPkgsTarget}/lib")
    else:
      raise newException(OSError, stowPkgsTargetEnvVar & " directory `" & stowPkgsTarget & "' does not exist")

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
            , GitSkip: bool=false
            , WaitSkip: bool=false
            , InstallSkip: bool=false
            , keep: bool=false
            , debug: bool=false) =
  ##NBuild: General purpose build script
  var revBase = rev.splitPath[1] #similar to basename in bash
  if debug: echo rev
  if debug: echo rev_base

  try:
    envVarCheck(pkg, debug)
    if (not GitSkip):
      gitOps(rev, revBase, debug)
    if (not WaitSkip):
      wait(debug=debug)
    setInstallDir(pkg, revBase, debug)
    make(pkg, debug)
    if (not InstallSkip):
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
  dispatch(nbuild)
