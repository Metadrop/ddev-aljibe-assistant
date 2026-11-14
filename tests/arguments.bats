#!/usr/bin/env bats

# Command line argument parsing tests.
#
# These tests only exercise parse_arguments() from create_project, so they do
# not need DDEV and run in seconds.

setup() {
  set -eu -o pipefail
  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-support

  # shellcheck disable=SC2155
  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"

  # create_project sources aljibe_includes, which is provided by the
  # ddev-aljibe add-on, from its own folder. Copy it next to an empty stub.
  export INCLUDES_DIR="${BATS_TEST_TMPDIR}/includes"
  mkdir -p "${INCLUDES_DIR}"
  cp "${DIR}/commands/host/includes/create_project" "${INCLUDES_DIR}/"
  touch "${INCLUDES_DIR}/aljibe_includes"
}

# Runs parse_arguments with the given arguments and prints the parsed values.
#
# A timeout makes a regression to an endless loop fail instead of hanging.
parse() {
  # shellcheck disable=SC2016
  run timeout 5 bash -c '
    source "${INCLUDES_DIR}/create_project"
    parse_arguments "$@"
    echo "name=[${PROJECT_NAME:-}] core=[${PROJECT_CORE:-}] profile=[${INSTALL_PROFILE:-}] extensions=[${PROVIDED_ALJIBE_EXTENSIONS:-}] auto=[${AUTO}]"
  ' _ "$@"
}

@test "options that need a value fail when it is missing" {
  for option in -n --name -c --core -e --extensions -p --profile; do
    parse "$option"
    assert_equal "$status" 1
    assert_output --partial "Error: option $option requires a value."
  done
}

@test "options that need a value do not take the next option as value" {
  for option in --name --core --extensions --profile; do
    parse "$option" --auto
    assert_equal "$status" 1
    assert_output --partial "Error: option $option requires a value."
  done
}

@test "options with values are parsed" {
  parse --auto --name myproject --core 10 --profile standard --extensions Metadrop/ddev-newman,ddev/ddev-adminer
  assert_success
  assert_output --partial "name=[myproject] core=[10] profile=[standard] extensions=[Metadrop/ddev-newman,ddev/ddev-adminer] auto=[1]"
}

@test "short options with values are parsed" {
  parse -a -n myproject -c 11 -p minimal -e NONE
  assert_success
  assert_output --partial "name=[myproject] core=[11] profile=[minimal] extensions=[[]] auto=[1]"
}

@test "invalid core version fails" {
  parse --core 12
  assert_equal "$status" 1
  assert_output --partial "Error: Invalid Drupal core version."
}

@test "unknown option fails" {
  parse --does-not-exist
  assert_equal "$status" 1
  assert_output --partial "Error: Unknown option --does-not-exist"
}
