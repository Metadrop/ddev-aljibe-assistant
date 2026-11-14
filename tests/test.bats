#!/usr/bin/env bats

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

  # ALJIBE_ADDON may point to a local ddev-aljibe checkout. DDEV needs an
  # absolute path, and the cwd changes below, so resolve it now.
  if [ -n "${ALJIBE_ADDON:-}" ] && [ -d "${ALJIBE_ADDON}" ]; then
    # shellcheck disable=SC2155
    export ALJIBE_ADDON="$(cd "${ALJIBE_ADDON}" && pwd)"
  fi

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


  ddev add-on get "${ALJIBE_ADDON:-metadrop/ddev-aljibe}"
  ddev add-on get ${DIR}
  ddev restart >/dev/null
}


# Checks if git is initialised.
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

  ddev add-on list --installed >&3


  for extension in "${extensions_list[@]}"; do
    # We grep using "│ " to filter the ADD-ON first column and to avoid partial
    # matches.
    echo "# Checking if extension $extension is installed (${extension//ddev-/})" >&3
    run bats_pipe ddev add-on list --installed \| grep "│ ${extension//ddev-/} " -c
    assert_output "1"
  done
}

# Checks the given extensions are not installed.
#
# Parameters:
#   $@: extension names, with or without the "ddev-" prefix.
check_extensions_not_installed() {
  local extension
  for extension in "$@"; do
    run bats_pipe ddev add-on list --installed \| grep -c "│ ${extension//ddev-/} "
    assert_output "0"
  done
}

# Checks Drupal is installed and the version matches expected.
#
# Parameters:
#   $1: expected_version - expected Drupal major version (e.g., 10 or 11)
# Checks phpunit.xml points the browser output to the project's folder.
#
# Drupal 10 uses an environment variable with an absolute (container) path,
# Drupal 11 an extension parameter with a path relative to phpunit.xml.
#
# Parameters:
#   $1: drupal_version - Drupal major version (10 or 11)
check_phpunit_output_directory() {
  if [ "$1" == "10" ]; then
    assert_file_contains "${TESTDIR}/phpunit.xml" '<env name="BROWSERTEST_OUTPUT_DIRECTORY" value="/var/www/html/web/sites/simpletest/browser_output"/>'
  else
    assert_file_contains "${TESTDIR}/phpunit.xml" '<parameter name="outputDirectory" value="web/sites/simpletest/browser_output"/>'
  fi
}

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
  check_phpunit_output_directory 11
}

@test "interactive mode with all defaults" {

  prepare_test "Running interactive mode with default values (pressing Enter)"

  # Simulate pressing Enter for all prompts (accept defaults)
  # The pipeline status is the assistant's, so 'yes' being killed by SIGPIPE
  # does not count as a failure.
  run bash -c 'yes "" | timeout 300 ddev aljibe-assistant --testing'
  assert_success

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
  check_phpunit_output_directory 10
}


@test "auto mode without git initialisation" {
  prepare_test "Testing without initialising git repository flag"

  # Use --git flag to skip git initialization
  run ddev aljibe-assistant --auto --git
  assert_success

  check_drupal_version 11
  check_git_is_no_initialised

  # GrumPHP hooks setup is skipped, so no stray .git folder is created.
  assert_dir_not_exists "${TESTDIR}/.git"
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

  run ddev aljibe-assistant --auto --extensions NONE
  assert_success

  check_drupal_version 11
  check_git_is_initialised
  check_extensions_not_installed adminer mkdocs selenium backstopjs pa11y unlighthouse newman yellowlabtools
}

@test "auto mode with selected add-ons" {

  prepare_test "Testing auto mode with selected extensions"

  run ddev aljibe-assistant --auto --extensions Metadrop/ddev-backstopjs,ddev/ddev-adminer
  assert_success

  check_drupal_version 11
  check_git_is_initialised
  check_extensions_installed backstopjs adminer
  check_extensions_not_installed mkdocs selenium pa11y unlighthouse newman yellowlabtools
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

  run ddev aljibe-assistant --auto --theme
  assert_success

  check_drupal_version 11
  check_git_is_initialised

  # Check if Artisan theme was installed
  run ddev composer show drupal/artisan
  assert_success

  # Check the subtheme was generated and set as the default theme
  assert_dir_exists "${TESTDIR}/web/themes/custom/artisan_subtheme"
  run ddev drush config:get system.theme default --format=string
  assert_output "artisan_subtheme"

  # Check the subtheme replaced the example theme in aljibe.yaml, so
  # 'ddev frontend' builds it.
  assert_file_contains "${TESTDIR}/.ddev/aljibe.yaml" "^  artisan_subtheme: /var/www/html/web/themes/custom/artisan_subtheme$"
  assert_file_not_contains "${TESTDIR}/.ddev/aljibe.yaml" "^  custom_theme:"
}

@test "auto mode stops and fails when a step fails" {
  prepare_test "Testing that a failing step aborts the assistant with an error"

  # A non-existent profile makes 'drush site-install' fail.
  run ddev aljibe-assistant --auto --extensions NONE --profile does_not_exist
  assert_failure
  assert_output --partial "Error: command failed"

  # Steps after the Drupal installation must not have run.
  assert_file_not_exists "${TESTDIR}/phpunit.xml"
}
