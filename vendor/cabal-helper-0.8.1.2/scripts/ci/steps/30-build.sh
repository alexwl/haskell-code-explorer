# -fdev enables building the helper "main" exe directly and enables more warnings
cabal --sandbox-config="$sandbox_config" configure --builddir="$build_dir" --enable-tests -fdev
cabal --sandbox-config="$sandbox_config" build     --builddir="$build_dir"
cabal --sandbox-config="$sandbox_config" haddock   --builddir="$build_dir"
