cabal_helper_libexecdir="$build_dir"/build/cabal-helper-wrapper \
    cabal --sandbox-config="$sandbox_config" test --builddir="$build_dir" --show-details=streaming
