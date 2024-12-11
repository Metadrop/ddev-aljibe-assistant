#!/bin/bash
# ddev-generated

# Constants
DRUSH_ALIASES_FOLDER="./drush/sites"
BEHAT_LOCAL_FOLDER="./tests/behat/local"
DRUPAL_VERSION=d11
PROJECT_TYPE=drupal11
PHP_VERSION="8.3"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color
PROJECT_NAME=${DDEV_PROJECT}

create_project() {
  local AUTO=$1

  echo -e "${GREEN}Launching assistant to configure the environment${NC}"
  echo ""

  configure_project
  setup_git
  init_ddev
  install_drupal
  create_behat_directories
  create_sub_theme
  init_grumphp
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
configure_project() {
  cd ${DDEV_APPROOT} || exit

  if [ "$AUTO" == "0" ]; then
    echo -e "${CYAN}Please enter the project name (default to ${DDEV_PROJECT}):${NC}"
    read PROJECT_NAME_INPUT
  fi

  if [ "$AUTO" == "0" ]; then
    echo -e "${CYAN}By default, Drupal 11 will be installed. Do you want to install Drupal 10 instead?${NC} [y/N]"
    read INSTALL_DRUPAL_10
    if [ "$INSTALL_DRUPAL_10" == "y" ] || [ "$INSTALL_DRUPAL_10" == "Y" ]; then
      DRUPAL_VERSION=d10
      PROJECT_TYPE=drupal10
      echo "** Drupal 10 will be installed **"
    else
      echo "** Drupal 11 will be installed **"
    fi
  fi

  echo "Configuring ddev environment"
  if [ -z "$PROJECT_NAME_INPUT" ]; then
    PROJECT_NAME_INPUT=${DDEV_PROJECT}
  fi
  PROJECT_NAME=$PROJECT_NAME_INPUT

  echo "Configuring ddev project $PROJECT_NAME"
  ddev config --project-type=$PROJECT_TYPE --php-version $PHP_VERSION --project-name $PROJECT_NAME --docroot 'web' --auto

  echo "Preparing Aljibe config file"
  cp ${DDEV_APPROOT}/.ddev/aljibe.yaml.example ${DDEV_APPROOT}/.ddev/aljibe.yaml
  sed -i "s/default_site\: self/default_site\: $PROJECT_NAME/g" ${DDEV_APPROOT}/.ddev/aljibe.yaml

  echo "Copying Aljibe Kickstart project files"
  ddev aljibe-kickstart --yes $DRUPAL_VERSION

  echo "Setting up Drush aliases file"
  cp "$DRUSH_ALIASES_FOLDER/sitename.site.yml.example" "$DRUSH_ALIASES_FOLDER/$PROJECT_NAME.site.yml"
  sed -i "s/example/$PROJECT_NAME/g" $DRUSH_ALIASES_FOLDER/$PROJECT_NAME.site.yml

  echo "Setting up behat.yml file"
  sed -i "s/example/$PROJECT_NAME/g" $BEHAT_LOCAL_FOLDER/behat.yml
}

# Setup git repo
setup_git() {
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

init_ddev() {
  ddev start
  ddev composer install
}

init_grumphp() {
  ddev exec grumphp git:init
}

install_drupal() {
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

create_behat_directories() {
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

create_sub_theme() {
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
