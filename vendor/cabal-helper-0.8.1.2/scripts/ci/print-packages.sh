if [ -e cabal.sandbox.config ]; then
    cabal sandbox hc-pkg list
else
    ghc-pkg list
fi
