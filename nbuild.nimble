# Package

version       = "0.1.0"
author        = "Kaushal Modi"
description   = "General purpose build script"
license       = "MIT"
srcDir        = "src"
bin           = @["nbuild"]

# Dependencies

requires "nim >= 0.19.0", "cligen >= 0.9.31", "parsetoml >= 0.5.0"
