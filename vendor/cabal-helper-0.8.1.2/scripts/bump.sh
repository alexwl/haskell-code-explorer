#!/bin/sh

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 VERSION" >&2
    exit 1
fi

VERSION=$1

if ! echo $VERSION | grep "^[0-9.]"; then
    echo "invalid version";
    exit 1
fi

cd $(dirname $0)/..

sed -r -i 's/^(version:[[:space:]]*)[0-9.]+/\1'"$VERSION"'/' cabal-helper.cabal

git add cabal-helper.cabal
git commit -m "Bump version to $VERSION"

git tag "v$VERSION"
