# Package

version       = "0.1.0"
author        = "kaushalmodi"
description   = "General purpose build script"
license       = "MIT"
srcDir        = "src"
bin = @["nbuild"]

# Dependencies

requires "nim >= 0.18.0", "cligen >= 0.9.11"
