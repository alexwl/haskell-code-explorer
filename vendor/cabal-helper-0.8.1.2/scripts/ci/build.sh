#!/bin/sh

set -ex

CI_SCRIPTS_DIR="$(realpath "$(dirname "$0")")"

for step in $(printf '%s\n' "$CI_SCRIPTS_DIR"/steps/* | sort); do
    . $step
done
