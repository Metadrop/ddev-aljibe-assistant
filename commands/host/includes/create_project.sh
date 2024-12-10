#!/bin/bash

# Constants
DRUSH_ALIASES_FOLDER="./drush/sites"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color
PROJECT_NAME=${DDEV_PROJECT}

create_project() {
  local AUTO=$1

  echo -e "${GREEN}Launching assistant to configure the environment${NC}"
  echo ""

  setConfFiles
  setUpGit
  initDdev
  installDrupal
  createDirectories
  createSubTheme
  initGrumpPhp
}

# Process example files
processExampleFile() {
  PATH=$1
  SUFFIX=$2
  declare -A REPLACEMENTS=$3
  cp "$PATH$SUFFIX" "$PATH"
  for KEY in "${!REPLACEMENTS[@]}"; do
    replaceInFile "$PATH" "$KEY" "${REPLACEMENTS[$KEY]}"
  done
}

# Setup several configuration files
setConfFiles() {
  cd ${DDEV_APPROOT} || exit

  if [ "$AUTO" == "0" ]; then
    echo -e "${CYAN}Please enter the project name (default to ${DDEV_PROJECT}):${NC}"
    read PROJECT_NAME_INPUT
  fi

  ddev config --php-version 8.3

  echo "Configuring ddev environment"

  if [ -z "$PROJECT_NAME_INPUT" ]; then
    PROJECT_NAME_INPUT=${DDEV_PROJECT}
  fi

  PROJECT_NAME=$PROJECT_NAME_INPUT

  echo "Configuring ddev project $PROJECT_NAME"
  ddev config --project-type=drupal --project-name $PROJECT_NAME --docroot 'web' --auto

  echo "Preparing Aljibe config file"
  cp ${DDEV_APPROOT}/.ddev/aljibe.yaml.example ${DDEV_APPROOT}/.ddev/aljibe.yaml
  sed -i "s/default_site\: self/default_site\: $PROJECT_NAME/g" ${DDEV_APPROOT}/.ddev/aljibe.yaml

  echo "Copying Aljibe Kickstart project files"
  ddev aljibe-kickstart --yes

  echo "Setting up Drush aliases file"
  cp "$DRUSH_ALIASES_FOLDER/sitename.site.yml.example" "$DRUSH_ALIASES_FOLDER/$PROJECT_NAME.site.yml"
  sed -i "s/example/$PROJECT_NAME/g" $DRUSH_ALIASES_FOLDER/$PROJECT_NAME.site.yml

  echo "Setting up behat.yml file"
  sed -i "s/example/$PROJECT_NAME/g" ./behat.yml

  echo "Setting up BackstopJS' cookies.json file"
  sed -i "s/example/$PROJECT_NAME/g" ./tests/functional/backstopjs/backstop_data/engine_scripts/cookies.json

  echo "Setting up phpunit.xml"
  cp "./phpunit.xml.dist" "./phpunit.xml"

  echo "Setting up phpmd.xml"
  cp "./phpmd.xml.dist" "./phpmd.xml"
}

# Setup git repo
setUpGit() {
  if [ "$AUTO" == "0" ]; then
    echo -e "${CYAN}Do you want to initialize a git repository for your new project?${NC} [Y/n]"
    read  INITIALIZE_GIT
  else
    INITIALIZE_GIT="n"
  fi

  if [ "$INITIALIZE_GIT" != "n" ]; then
    ## Init with main branch
    git init -b main
    ## Create develop branch
    git checkout -b develop
  fi
}

initDdev() {
  ddev start
  ddev composer install
}

initGrumpPhp() {
  ddev exec grumphp git:init
}

installDrupal() {
  if [ "$AUTO" == "0" ]; then
    echo -e "${CYAN}Do you want to install Drupal?${NC} [Y/n]"
    read INSTALL_DRUPAL
    if [ "$INSTALL_DRUPAL" != "n" ]; then
      AVAILABLE_PROFILES=("minimal" "standard" "demo_umami")
      echo -e "${CYAN}What install profile you want to install?${NC}"
      select PROFILE in "${AVAILABLE_PROFILES[@]}"; do
        echo "Installing profile $PROFILE"
        ddev drush -y si $PROFILE
        ddev drush cr
        break
      done
    fi
  else
    PROFILE="standard"
    echo "Installing profile $PROFILE"
    ddev drush -y si $PROFILE
    ddev drush cr
  fi
}

createDirectories() {
  BEHAT_DIR="./web/sites/default/files/behat"
  BEHAT_DIR_ERRORS="$BEHAT_DIR/errors"

  if [ ! -d "$BEHAT_DIR" ]; then
    mkdir -p "$BEHAT_DIR"
    chmod 755 "$BEHAT_DIR"
  fi

  if [ ! -d "$BEHAT_DIR_ERRORS" ]; then
    mkdir -p "$BEHAT_DIR_ERRORS"
    chmod 755 "$BEHAT_DIR_ERRORS"
  fi
}

createSubTheme() {
  if [ "$AUTO" == "0" ]; then
    echo -e "${CYAN}Do you want to create a Radix sub-theme?${NC} [Y/n] "
    read CREATE_SUB_THEME
  else
    CREATE_SUB_THEME="n"
  fi

  if [ "$CREATE_SUB_THEME" != "n" ]; then
    DEFAULT_THEME_NAME=$(echo "${PROJECT_NAME}_radix" | tr '-' '_')
    echo -e "${CYAN}Please enter the new theme name (default to ${DEFAULT_THEME_NAME})?${NC}"
    read THEME_NAME
    if [ -z "$THEME_NAME" ]; then
        THEME_NAME="${DEFAULT_THEME_NAME}"
    fi
    THEME_NAME=$(echo "$THEME_NAME" | tr -dc '[:alnum:]_')
    ddev drush en components
    ddev drush theme:enable radix -y
    ddev drush --include="web/themes/contrib/radix" radix:create $THEME_NAME
    ddev drush theme:enable $THEME_NAME -y
    ddev drush config-set system.theme default $THEME_NAME -y
    # Add theme to aljibe.yml
    sed -i "s/custom_theme/$THEME_NAME/g" ${DDEV_APPROOT}/.ddev/aljibe.yaml
    ddev restart
    ddev frontend dev
  fi
}
