Automatic duplicate file finder

```
Usage:
  main [optional-params] directories to search
Options:
  -h, --help                          print this cligen-erated help
  --help-syntax                       advanced: prepend,plurals,..
  -D, --duplicate      bool    false  search for duplicate files
  -E, --empty          bool    false  search for empty directories
  -M, --music          bool    false  search for duplicate music files
  -p=, --pattern=      string  ""     include those containing pattern in filename
  -r=, --regex=        string  ""     include those containing regex in fileame
  -P=, --patternfull=  string  ""     include those containing pattern in path
  -R=, --regexfull=    string  ""     include those containing regex in path
  -g=, --greater=      int     0      include size greater than (bytes)
  -l=, --lesser=       int     0      include size lesser than (bytes)
  -a=, --after=        int     0      include last modified after (days)
  -b=, --before=       int     0      include last modified before (days)
  -m=, --move=         string  ""     move results to
  -c=, --copy=         string  ""     copy results to
  -x, --delete         bool    false  delete results
  -i=, --invert=       string  ""     invert specified flags
  -q, --quiet          bool    false  quiet - do not display results
  ```