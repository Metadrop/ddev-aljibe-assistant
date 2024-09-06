setup() {
  set -eu -o pipefail
  export DIR
  DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )/.."
  export TESTDIR=~/tmp/test-addon-aljibe-assistant
  mkdir -p $TESTDIR
  export PROJNAME=test-addon-aljibe-assistant
  export DDEV_NON_INTERACTIVE=true
  ddev delete -Oy ${PROJNAME} >/dev/null 2>&1 || true
  cd "${TESTDIR}"
  ddev config --project-name=${PROJNAME}
  ddev start -y >/dev/null
}

teardown() {
  set -eu -o pipefail
  cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
  ddev delete -Oy ${PROJNAME} >/dev/null 2>&1
  [ "${TESTDIR}" != "" ] && rm -rf ${TESTDIR}
}

@test "install from directory" {
  set -eu -o pipefail
  cd ${TESTDIR}
  echo "# Installing aljibe with local aljibe assistant" >&3
  ddev get metadrop/ddev-aljibe
  # Overwrite assistant with local version
  ddev get ${DIR}
  ddev restart >/dev/null
  ddev aljibe-assistant --auto >&3
}

@test "install from release" {
  set -eu -o pipefail
  cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
  echo "# Installing aljibe with latest release of aljibe assistant" >&3
  ddev get metadrop/ddev-aljibe
  ddev restart >/dev/null
  # Do something useful here that verifies the add-on
  ddev aljibe-assistant --auto >&3
}
