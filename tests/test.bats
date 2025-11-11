#!/bin/bash

# Standard DDEV add-on setup code taken from official DDEV add-ons.
setup() {
  set -eu -o pipefail
  export GITHUB_REPO=Metadrop/ddev-aljibe-assistant
  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  # shellcheck disable=SC2155
  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  # shellcheck disable=SC2155
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"

  mkdir -p ~/tmp
  # shellcheck disable=SC2155
  export TESTDIR=$(mktemp -d ~/tmp/${PROJNAME}.XXXXXX)
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true

  cd "${TESTDIR}"
  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site
  assert_success
  run ddev start -y
  assert_success

  # Configure GitHub token for composer to avoid rate limiting
  # The token is passed as an environment variable from GitHub Actions
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "# Configuring composer with GitHub token to avoid rate limiting" >&3
    echo "{\"github-oauth\": {\"github.com\": \"${GITHUB_TOKEN}\"}}" > auth.json
  fi
}


# Standard DDEV add-on tear down code taken from official DDEV add-ons.
teardown() {
  set -eu -o pipefail
  echo "# Tearing down test environment" >&3
  cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
  ddev delete -Oy ${PROJNAME} >/dev/null 2>&1
  cd ..
  [ "${TESTDIR}" != "" ] && rm -rf ${TESTDIR}
  echo "# Teardown complete" >&3
}


# Common actions before running a tests.
#
# Sets the corerct bash flags, displays the test title, and installs Aljibe
# add-on. Because Assistant is overwritten with the published version (because
# Assistant is a dependency of Aljibe) the tested version of Assistant is copied
# over the installed one.
#
# Parameters:
#   $1: test_title - title of the test being prepared
prepare_test() {

  local test_title
  test_title="$1"

  set -eu -o pipefail

  cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
  echo "# $test_title" >&3


  ddev add-on get metadrop/ddev-aljibe
  ddev add-on get ${DIR}
  ddev restart >/dev/null
}


# Checks if git is initialised.
#
# It checks for .git/config because Aljibe adds git hooks, so .git folder will
# always be present.
is_git_initialised() {
  if [ -d ".git" ] && [ -f ".git/config" ]; then
    return 0
  else
    return 1
  fi
}

check_git_is_initialised() {
  run is_git_initialised
  assert_success
}

check_git_is_no_initialised() {
  run is_git_initialised
  assert_failure
}


check_extensions_installed() {
  local extensions_list
  extensions_list=("$@")

  echo "Installed extensions!" >&3
  ddev add-on list --installed >&3


  for extension in "${extensions_list[@]}"; do
    # We grep using "│ " to filter the ADD-ON first column and to avoid partial
    # matches.
    echo "# Checking if extension $extension is installed (${extension//ddev-/})" >&3
    run bats_pipe ddev add-on list --installed \| grep "│ ${extension//ddev-/} " -c
    assert_output "1"
  done
}

# Checks Drupal is installed and the version matches expected.
#
# Parameters:
#   $1: expected_version - expected Drupal major version (e.g., 10 or 11)
check_drupal_version() {
  local expected_version="$1"

  # Verify Drupal was installed
  run ddev drush status --field=bootstrap
  assert_output "Successful"

  # Verify version
  run ddev drush status --field=drupal-version
  assert_output --regexp "^${expected_version}\."
}


@test "install from directory" {
  prepare_test "Installing aljibe with local aljibe assistant"

  run ddev aljibe-assistant --auto >&3
  assert_success

  check_drupal_version 11
  check_git_is_initialised
}

@test "interactive mode with all defaults" {

  prepare_test "Running interactive mode with default values (pressing Enter)"

  # Simulate pressing Enter for all prompts (accept defaults)
  yes "" | timeout 300 ddev aljibe-assistant --testing >&3 || true

  check_drupal_version 11
  check_git_is_initialised
}


@test "auto mode with Drupal 10" {

  prepare_test "Testing auto mode with Drupal 10 flag"

  # Use --core flag to install Drupal 10
  run ddev aljibe-assistant --auto --core 10 >&3
  assert_success

  check_drupal_version 10
  check_git_is_initialised
}


@test "auto mode without git initialisation" {
  prepare_test "Testing without initialising git repository flag"

  # Use --git flag to skip git initialization
  ddev aljibe-assistant --auto --git >&3
  assert_success

  check_drupal_version 11
  check_git_is_no_initialised
}


@test "auto mode without installing Drupal" {

  prepare_test "Testing auto mode with --install flag to skip Drupal installation"

  # Use --install flag to skip Drupal installation
  ddev aljibe-assistant --auto --install >&3
  assert_success

  # Verify Drupal was NOT installed (bootstrap should not be successful)
  run ddev drush status --field=bootstrap 2>&1
  refute_output "Successful"
}

@test "auto mode without any add-ons" {

  prepare_test "Testing auto mode with no extensions"

  ddev aljibe-assistant --auto --extensions NONE >&3
  assert_success

  check_drupal_version 11
  check_git_is_initialised
  check_extensions_installed
}

@test "auto mode with selected add-ons" {

  prepare_test "Testing auto mode with selected extensions"

  ddev aljibe-assistant --auto --extensions Metadrop/ddev-backstopjs,ddev/ddev-adminer >&3
  assert_success

  check_drupal_version 11
  check_git_is_initialised
  check_extensions_installed backstopjs adminer
}


@test "auto mode with specific install profile" {

  prepare_test "Testing auto mode with --profile flag"

  ddev aljibe-assistant --auto --profile demo_umami >&3
  assert_success

  check_drupal_version 11
  check_git_is_initialised
}


@test "auto mode with Artisan theme" {

  prepare_test "Testing auto mode with --theme flag"

  ddev aljibe-assistant --auto --theme >&3
  assert_success

  check_drupal_version 11
  check_git_is_initialised

  # Check if Artisan theme was installed
  run ddev composer show drupal/artisan
  assert_success
}
