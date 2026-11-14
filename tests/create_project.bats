#!/usr/bin/env bats

# Unit tests for functions in commands/host/includes/create_project.
#
# These tests call the functions directly, so they do not need DDEV and run in
# seconds.

setup() {
  set -eu -o pipefail
  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-support
  bats_load_library bats-file

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
  assert_output --partial "name=[myproject] core=[11] profile=[minimal] extensions=[NONE] auto=[1]"
}

@test "flags that skip a step say so" {
  parse --install --git
  assert_success
  assert_output --partial "Drupal will NOT be installed"
  assert_output --partial "Git repository will NOT be initialized"
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

# Puts a sed that follows BSD (macOS) rules for -i first in PATH: "-i EXT"
# takes the next argument as the backup suffix and "-iEXT" an attached one.
# It then runs GNU sed with the equivalent options.
fake_bsd_sed() {
  local stub_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stub_dir}"
  cat > "${stub_dir}/sed" <<EOF
#!/bin/bash
if [ "\$1" = "-i" ]; then
  suffix="\$2"
  shift 2
elif [[ "\$1" == -i* ]]; then
  suffix="\${1#-i}"
  shift
fi
exec $(command -v sed) "-i\${suffix}" "\$@"
EOF
  chmod +x "${stub_dir}/sed"
  export PATH="${stub_dir}:${PATH}"
}

# Runs os_custom_sed on a file in an empty folder and checks the result.
check_os_custom_sed() {
  local work_dir="${BATS_TEST_TMPDIR}/work"
  mkdir -p "${work_dir}"
  echo "default_site: self" > "${work_dir}/aljibe.yaml"

  # shellcheck disable=SC2016
  run bash -c '
    source "${INCLUDES_DIR}/create_project"
    os_custom_sed "s/self/myproject/g" "$1"
  ' _ "${work_dir}/aljibe.yaml"
  assert_success

  run cat "${work_dir}/aljibe.yaml"
  assert_output "default_site: myproject"

  # No backup or other stray files are left next to the edited file.
  run ls -A "${work_dir}"
  assert_output "aljibe.yaml"
}

@test "os_custom_sed edits in place without leaving backups (GNU sed)" {
  check_os_custom_sed
}

@test "os_custom_sed edits in place without leaving backups (BSD sed)" {
  fake_bsd_sed
  check_os_custom_sed
}

# Runs grumphp_setup in a temporary project with a ddev stub that logs calls.
run_grumphp_setup() {
  local stub_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stub_dir}"
  export DDEV_CALLS_LOG="${BATS_TEST_TMPDIR}/ddev-calls.log"
  : > "${DDEV_CALLS_LOG}"
  printf '#!/bin/bash\necho "$*" >> "${DDEV_CALLS_LOG}"\n' > "${stub_dir}/ddev"
  chmod +x "${stub_dir}/ddev"

  # shellcheck disable=SC2016
  PATH="${stub_dir}:${PATH}" GIT_CEILING_DIRECTORIES="${BATS_TEST_TMPDIR}" run bash -c '
    source "${INCLUDES_DIR}/create_project"
    grumphp_setup
  '
}

@test "grumphp_setup sets up hooks in a git repository" {
  export DDEV_APPROOT="${BATS_TEST_TMPDIR}/project"
  mkdir -p "${DDEV_APPROOT}"
  git -C "${DDEV_APPROOT}" init -q

  run_grumphp_setup
  assert_success

  run cat "${DDEV_CALLS_LOG}"
  assert_output "exec grumphp git:init"
}

@test "grumphp_setup removes the hooks folder left by GrumPHP outside a git repository" {
  export DDEV_APPROOT="${BATS_TEST_TMPDIR}/project"
  mkdir -p "${DDEV_APPROOT}/.git/hooks"
  touch "${DDEV_APPROOT}/.git/hooks/pre-commit"

  run_grumphp_setup
  assert_success
  assert_output --partial "Not a git repository"
  assert_dir_not_exists "${DDEV_APPROOT}/.git"

  run cat "${DDEV_CALLS_LOG}"
  assert_output ""
}

@test "grumphp_setup keeps other .git contents outside a git repository" {
  export DDEV_APPROOT="${BATS_TEST_TMPDIR}/project"
  mkdir -p "${DDEV_APPROOT}/.git/hooks"
  touch "${DDEV_APPROOT}/.git/something-else"

  run_grumphp_setup
  assert_success
  assert_dir_not_exists "${DDEV_APPROOT}/.git/hooks"
  assert_file_exists "${DDEV_APPROOT}/.git/something-else"
}

# Runs aljibe_extensions_setup with the given --extensions value, using a ddev
# stub that logs calls and reports no installed add-ons.
run_extensions_setup() {
  local stub_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stub_dir}"
  export DDEV_CALLS_LOG="${BATS_TEST_TMPDIR}/ddev-calls.log"
  : > "${DDEV_CALLS_LOG}"
  printf '#!/bin/bash\necho "$*" >> "${DDEV_CALLS_LOG}"\n' > "${stub_dir}/ddev"
  chmod +x "${stub_dir}/ddev"

  # shellcheck disable=SC2016
  PATH="${stub_dir}:${PATH}" run bash -c '
    source "${INCLUDES_DIR}/create_project"
    AUTO=1
    PROVIDED_ALJIBE_EXTENSIONS="$1"
    aljibe_extensions_setup
  ' _ "$1"
}

@test "extensions NONE installs no extension" {
  run_extensions_setup NONE
  assert_success

  run grep -c "^add-on get" "${DDEV_CALLS_LOG}"
  assert_output "0"
}

@test "extensions list installs only the listed extensions" {
  run_extensions_setup "Metadrop/ddev-newman,ddev/ddev-adminer"
  assert_success
  refute_output --partial "Warning"

  run grep "^add-on get" "${DDEV_CALLS_LOG}"
  assert_output "add-on get ddev/ddev-adminer
add-on get Metadrop/ddev-newman"
}

@test "extensions list warns about unknown extensions" {
  run_extensions_setup "Metadrop/ddev-newmann,ddev/ddev-adminer"
  assert_success
  assert_output --partial "Warning: unknown extension 'Metadrop/ddev-newmann' ignored."

  run grep "^add-on get" "${DDEV_CALLS_LOG}"
  assert_output "add-on get ddev/ddev-adminer"
}
