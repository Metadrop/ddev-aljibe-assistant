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
}

# Standard DDEV add-on tear down code taken from official DDEV add-ons.
teardown() {
  set -eu -o pipefail
  echo "# Tearing down test environment" >&3
  cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
  ddev delete -Oy ${PROJNAME} >/dev/null 2>&1
  [ "${TESTDIR}" != "" ] && rm -rf ${TESTDIR}
  echo "# Teardown complete" >&3
}

# Checks Aljibe assistant runs in auto mode successfully.
check_assistant_run_auto_mode() {
  ddev aljibe-assistant --auto >&3
  assert_success
}

@test "install from directory" {
  set -eu -o pipefail
  cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
  echo "# Installing aljibe with local aljibe assistant" >&3

  ddev add-on get metadrop/ddev-aljibe

  # Overwrite assistant with local version
  ddev add-on get ${DIR}

  ddev restart >/dev/null

  check_assistant_run_auto_mode
}


# Test Drupal 10 installation using flag
@test "auto mode with Drupal 10" {
  set -eu -o pipefail
  cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
  echo "# Testing auto mode with Drupal 10 flag" >&3

  ddev add-on get metadrop/ddev-aljibe
  ddev add-on get ${DIR}
  ddev restart >/dev/null

  # Use --core flag to install Drupal 10
  ddev aljibe-assistant --auto --core 10 >&3
  assert_success

  # Verify Drupal was installed
  run ddev drush status --field=bootstrap
  assert_output "Successful"

  # Verify it's Drupal 10
  run ddev drush status --field=drupal-version
  assert_output --regexp "^10\."
}

# # Test without git initialization using flag
# @test "auto mode without git initialization" {
#   set -eu -o pipefail
#   cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
#   echo "# Testing auto mode with --git flag to skip git repo" >&3

#   ddev add-on get metadrop/ddev-aljibe
#   ddev add-on get ${DIR}
#   ddev restart >/dev/null

#   # Use --git flag to skip git initialization
#   ddev aljibe-assistant --auto --git >&3
#   assert_success

#   # Verify no git repo was created
#   run test -d .git
#   assert_failure
# }

# # Test without Drupal installation using flag
# @test "auto mode without Drupal installation" {
#   set -eu -o pipefail
#   cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
#   echo "# Testing auto mode with --install flag to skip Drupal" >&3

#   ddev add-on get metadrop/ddev-aljibe
#   ddev add-on get ${DIR}
#   ddev restart >/dev/null

#   # Use --install flag to skip Drupal installation
#   ddev aljibe-assistant --auto --install >&3
#   assert_success

#   # Verify Drupal was NOT installed (bootstrap should not be successful)
#   run ddev drush status --field=bootstrap 2>&1
#   refute_output "Successful"
# }

# # Test with specific install profile using flag
# @test "auto mode with specific install profile" {
#   set -eu -o pipefail
#   cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
#   echo "# Testing auto mode with --profile flag" >&3

#   ddev add-on get metadrop/ddev-aljibe
#   ddev add-on get ${DIR}
#   ddev restart >/dev/null

#   # Use --profile flag to install standard profile instead of minimal
#   ddev aljibe-assistant --auto --profile standard >&3
#   assert_success

#   # Verify Drupal was installed successfully
#   run ddev drush status --field=bootstrap
#   assert_output "Successful"
# }

# # Test with Artisan theme installation using flag
# @test "auto mode with Artisan theme" {
#   set -eu -o pipefail
#   cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
#   echo "# Testing auto mode with --theme flag" >&3

#   ddev add-on get metadrop/ddev-aljibe
#   ddev add-on get ${DIR}
#   ddev restart >/dev/null

#   # Use --theme flag to install Artisan theme
#   ddev aljibe-assistant --auto --theme >&3
#   assert_success

#   # Verify Drupal was installed successfully
#   run ddev drush status --field=bootstrap
#   assert_output "Successful"

#   # Check if Artisan theme was installed
#   run ddev composer show drupal/artisan
#   assert_success
# }

# # Test combining multiple flags
# @test "auto mode with multiple custom flags" {
#   set -eu -o pipefail
#   cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
#   echo "# Testing auto mode with multiple flags combined" >&3

#   ddev add-on get metadrop/ddev-aljibe
#   ddev add-on get ${DIR}
#   ddev restart >/dev/null

#   # Combine multiple flags: custom name, Drupal 10, standard profile, no git
#   ddev aljibe-assistant --auto --name "multi-flag-test" --core 10 --profile standard --git >&3
#   assert_success

#   # Verify Drupal 10 was installed
#   run ddev drush status --field=bootstrap
#   assert_output "Successful"

#   run ddev drush status --field=drupal-version
#   assert_output --regexp "^10\."

#   # Verify no git repo
#   run test -d .git
#   assert_failure
# }