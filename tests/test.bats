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
  cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
  ddev delete -Oy ${PROJNAME} >/dev/null 2>&1
  [ "${TESTDIR}" != "" ] && rm -rf ${TESTDIR}
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

@test "install from release" {
  set -eu -o pipefail
  cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
  echo "# Installing aljibe with latest release of aljibe assistant" >&3

  # Install from release.
  ddev add-on get metadrop/ddev-aljibe
  ddev restart >/dev/null

  check_assistant_run_auto_mode
}

# Test interactive mode with all defaults (just pressing Enter)
@test "interactive mode with all defaults" {
  set -eu -o pipefail
  cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
  echo "# Installing aljibe and testing interactive mode with defaults" >&3

  ddev add-on get metadrop/ddev-aljibe
  ddev add-on get ${DIR}
  ddev restart >/dev/null

  # Simulate pressing Enter for all prompts (accept defaults)
  # This uses 'yes' to send empty lines (Enter key presses)
  echo "# Running interactive mode with default values (pressing Enter)" >&3
  yes "" | timeout 300 ddev aljibe-assistant >&3 || true

  # Verify the project was created successfully
  run ddev drush status --field=bootstrap
  assert_output "Successful"
}

# Test interactive mode with custom project name
@test "interactive mode with custom project name" {
  set -eu -o pipefail
  cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
  echo "# Testing interactive mode with custom project name" >&3

  ddev add-on get metadrop/ddev-aljibe
  ddev add-on get ${DIR}
  ddev restart >/dev/null

  # Simulate user input: custom project name, then defaults for everything else
  # Input sequence:
  # 1. "custom-project" - custom project name
  # 2. "" (Enter) - accept Drupal 11 (default)
  # 3. "" (Enter) - initialize git repo (default)
  # 4. Enter - accept default extensions
  # 5. "" (Enter) - install Drupal (default)
  # 6. "1" - select Minimal profile
  # 7. "" (Enter) - don't create Artisan subtheme (default)
  echo "# Running with custom project name" >&3
  {
    echo "custom-project"
    yes ""
  } | timeout 300 ddev aljibe-assistant >&3 || true

  # Verify bootstrap is successful
  run ddev drush status --field=bootstrap
  assert_output "Successful"
}

# Test interactive mode choosing Drupal 10
@test "interactive mode with Drupal 10 selection" {
  set -eu -o pipefail
  cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
  echo "# Testing interactive mode with Drupal 10 selection" >&3

  ddev add-on get metadrop/ddev-aljibe
  ddev add-on get ${DIR}
  ddev restart >/dev/null

  # Input sequence:
  # 1. "" (Enter) - use default project name
  # 2. "y" - install Drupal 10 instead of 11
  # 3. Then defaults for everything else
  echo "# Running with Drupal 10 selection" >&3
  {
    echo ""
    echo "y"
    yes ""
  } | timeout 300 ddev aljibe-assistant >&3 || true

  # Verify Drupal was installed
  run ddev drush status --field=bootstrap
  assert_output "Successful"

  # Verify it's Drupal 10
  run ddev drush status --field=drupal-version
  assert_output --regexp "^10\."
}

# Test interactive mode skipping git initialization
@test "interactive mode without git initialization" {
  set -eu -o pipefail
  cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
  echo "# Testing interactive mode without git initialization" >&3

  ddev add-on get metadrop/ddev-aljibe
  ddev add-on get ${DIR}
  ddev restart >/dev/null

  # Input sequence:
  # 1. "" (Enter) - default project name
  # 2. "" (Enter) - Drupal 11
  # 3. "n" - don't initialize git
  # 4. Then defaults for everything else
  echo "# Running without git initialization" >&3
  {
    echo ""
    echo ""
    echo "n"
    yes ""
  } | timeout 300 ddev aljibe-assistant >&3 || true

  # Verify no git repo was created
  run test -d .git
  assert_failure
}

# Test interactive mode skipping Drupal installation
@test "interactive mode without Drupal installation" {
  set -eu -o pipefail
  cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
  echo "# Testing interactive mode without Drupal installation" >&3

  ddev add-on get metadrop/ddev-aljibe
  ddev add-on get ${DIR}
  ddev restart >/dev/null

  # Input sequence:
  # 1. "" (Enter) - default project name
  # 2. "" (Enter) - Drupal 11
  # 3. "" (Enter) - initialize git
  # 4. Enter - accept default extensions
  # 5. "n" - don't install Drupal
  # 6. "" (Enter) - don't create Artisan subtheme
  echo "# Running without Drupal installation" >&3
  {
    echo ""
    echo ""
    echo ""
    echo ""
    echo "n"
    echo ""
  } | timeout 300 ddev aljibe-assistant >&3 || true

  # Verify Drupal was NOT installed (bootstrap should not be successful)
  run ddev drush status --field=bootstrap 2>&1
  refute_output "Successful"
}
