mkdir -p "$source_dir"
mkdir -p "$build_dir"

cabal --sandbox-config="$sandbox_config" sdist --builddir="$build_dir" --output-directory="$source_dir"

cd "$source_dir"
