# Package

version     = "0.1.0"
author      = "genotrance"
description = "Duplicate file finder"
license     = "MIT"

bin = @["autodup"]

# Dependencies

requires "nim >= 1.0.8", "cligen >= 1.1.0", "regex >= 0.15.0", "weave#head"
