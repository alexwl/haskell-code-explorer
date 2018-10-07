"$CI_SCRIPTS_DIR"/retry.sh  cabal update
cabal --sandbox-config="$sandbox_config" sandbox init --sandbox="$sandbox"
cabal --sandbox-config="$sandbox_config" install --only-dependencies --enable-tests
