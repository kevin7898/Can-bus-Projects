#!/bin/sh
set -eu
tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
test_build=$(mktemp -d)
trap 'rm -rf "$test_build"' EXIT HUP INT TERM
for test in power_policy config_key; do
    "${CC:-cc}" -std=c11 -Wall -Wextra -Werror "$tests_dir/${test}_test.c" -o "$test_build/$test"
    "$test_build/$test"
done
