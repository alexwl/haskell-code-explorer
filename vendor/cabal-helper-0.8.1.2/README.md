# cabal-helper
[![build status](https://gitlab.com/dxld/cabal-helper/badges/master/build.svg)](https://gitlab.com/dxld/cabal-helper/commits/master)

Cabal's little helper provides access to build information gathered by `cabal`
when configuring a project. Specifically we're interested in retrieving enough
information to bring up a compiler session, using the GHC API, which is similar
to running `cabal repl` in a project.

While simple in principle this is complicated by the fact that the information
Cabal writes to disk is in an unstable format and only really accessible through
the Cabal API itself.

Since we do not want to bind the user of a development tool which utilises this
library to a specific version of Cabal we compile the code which interfaces with
the Cabal library's API on the user's machine, at runtime, against whichever
version of Cabal was used to write the on disk information for a given project.

If this version of Cabal is not available on the users machine anymore, which is
fairly likely since cabal-install is usually linked statically, we have support
for compiling the Cabal library also. In this case the library is installed into
a private, isolated, package database in `$XDG_CACHE_HOME/cabal-helper` so as to
not interfere with the user's package database.

## IRC

If you have any problems, suggestions, comments swing by
[\#ghc-mod (web client)](https://kiwiirc.com/client/irc.freenode.org/ghc-mod) on
Freenode. If you're reporting a bug please also create an issue
[here](https://github.com/DanielG/cabal-helper/issues) so we have a way to
contact you if you don't have time to stay.

Do hang around for a while if no one answers and repeat your question if you
still haven't gotten any answer after a day or so. You're most likely to get an
answer during the day in GMT+1.
