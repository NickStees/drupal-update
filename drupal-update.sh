#!/bin/bash
###############################################################################
# GNU General Public License v3.0                                             #
# Copyright (c) 2023 Valentino Međimorec                                      #
#                                                                             #
# Simplistic script to use with GitHub Actions or standalone                  #
# to perform composer updates of Drupal projects.                             #
#                                                                             #
# Standalone usage                                                            #
# Run minor updates                  -> bash drupal-update.sh                 #
# Run all updates                    -> bash drupal-update.sh -t all          #
# Run updates, except core           -> bash drupal-update.sh -t all -c false #
# Run with ddev prefix               -> bash drupal-update.sh -p ddev         #                                                                          #
###############################################################################

set -e

RESULT_SUCCESS="success"
RESULT_PATCH_FAILURE="patch failure"
RESULT_GENERIC_ERROR="generic error"
RESULT_DEPENDENCY_ERROR="failed dependency"
RESULT_UNKNOWN="unknown"
RESULT_SKIP="skipped"

# Function to display script usage.
usage() {
 echo "Usage: $0 [OPTIONS]"
 echo "Options:"
 echo " -h, --help      Display this help message"
 echo " -t, --type      Options: semver-safe-update or all. Default is semver-safe-update: minor and security upgrades."
 echo " -o, --output    Specify an output file to save summary. Default is none."
 echo " -c, --core      Flag to enable or disable Drupal core upgrades check. Default is true."
 echo " -e, --exclude   Exclude certain modules from updates check. Use comma-separated list: token,redirect,pathauto"
 echo " -p, --prefix    Prefix for composer commands. Example: 'ddev' for 'ddev composer update'. Default is none."
}

# Exit with error.
exit_error() {
  usage
  exit 1
}

# Validate options passed by GitHub or by standalone usage with flags.
validate_options() {
    UPDATE_TYPE=$1
    UPDATE_CORE=$2
    UPDATE_EXCLUDE=$3
    SUMMARY_FILE=$4
    COMPOSER_PREFIX=$5

    if  [ -n "$UPDATE_TYPE" ] && [ "$UPDATE_TYPE" != "semver-safe-update" ] && [ "$UPDATE_TYPE" != "all" ]; then
      echo "Error: Update type can be either semver-safe-update or all"
      exit_error
    fi

    if [ -n "$UPDATE_CORE" ] && [ "$UPDATE_CORE" != true ] && [ "$UPDATE_CORE" != false ]; then
      echo "Error: Core flag must be either true or false. Default if empty is false"
      exit_error
    fi

    if [ -n "$SUMMARY_FILE" ] && [[ "$SUMMARY_FILE" != *.md ]]; then
      echo "Error: Summary output file needs to end with .md extension."
      exit_error
    fi
}

# Validate if all requirements are present.
# Check the existence of composer.json/lock file, composer, sed, and jq binaries.
validate_requirements() {
  if [ ! -f composer.json ] || [ ! -f composer.lock ]; then
    echo "Error: composer.json or composer.lock are missing."
    exit 1
  fi

  local BINARIES="php composer sed grep jq";
  local BINARY
  for BINARY in $BINARIES
  do
    if ! [ -x "$(command -v "$BINARY")" ]; then
      echo "Error: $BINARY is not installed."
      exit 1
    fi
  done

}

# Handles output from Composer, and assign corresponding status.
composer_output() {
  local COMPOSER_OUTPUT
  local PROJECT_NAME
  local LATEST_VERSION
  local UPDATE_STATUS
  local PATCH_LIST
  PROJECT_NAME=$1
  LATEST_VERSION=$2
  UPDATE_STATUS=$3
  PATCH_LIST=$4

    # Handle specific case for Drupal core.
  if [ "$PROJECT_NAME" = "drupal/core" ]; then
    if [ "$UPDATE_TYPE" == "all" ] && [ "$UPDATE_STATUS" == "update-possible" ]; then
      COMPOSER_OUTPUT=$($COMPOSER_PREFIX composer require drupal/core-recommended:"$LATEST_VERSION" drupal/core-composer-scaffold:"$LATEST_VERSION" drupal/core-project-message:"$LATEST_VERSION" -W -q -n --ignore-platform-reqs)
    else
      COMPOSER_OUTPUT=$($COMPOSER_PREFIX composer update drupal/core-* -W -q -n --ignore-platform-reqs)
    fi
  else
    if [ "$UPDATE_STATUS" == "update-possible" ]; then
      COMPOSER_OUTPUT=$($COMPOSER_PREFIX composer require "$PROJECT_NAME":"$LATEST_VERSION" -W -q -n --ignore-platform-reqs)
    else
      COMPOSER_OUTPUT=$($COMPOSER_PREFIX composer update "$PROJECT_NAME" -W -q -n --ignore-platform-reqs)
    fi
  fi

  local EXIT_CODE=$?;

  case "$EXIT_CODE" in
    0)
      echo $RESULT_SUCCESS
    ;;
    1)
      local RESULT
      # Do a sanity check before comparing patches.
      if [[ $LATEST_VERSION == dev-* ]]; then
        RESULT=$RESULT_SUCCESS
      elif grep -q "$LATEST_VERSION" composer.lock; then
        RESULT=$RESULT_SUCCESS
      else
        RESULT=$RESULT_GENERIC_ERROR
      fi

      # Compare the list of patches. We need to compare them because if previous
      # one failed; composer install is going to throw an error.
      if [ -n "$PATCH_LIST" ]; then
        local PATCH=
        for PATCH in $(echo "${PATCH_LIST}" | jq -c '.[]'); do
           if [ "$(grep -s -c -ic "$PATCH" "$COMPOSER_OUTPUT")" != 0 ]; then
             RESULT="$PATCH"
           else
             continue
           fi
        done
      fi
      echo "$RESULT"
    ;;
    2)
      echo "$RESULT_DEPENDENCY_ERROR"
    ;;
    *)
      echo "$RESULT_UNKNOWN"
  esac
}

# Update or skip project per different criteria.
update_project() {
  local COMPOSER_PACKAGE=$1
  declare -n RESULT_TABLE=$2
  declare -n RESULT_HIGHLIGHTS=$3
  local RESULT_STATUS=$RESULT_SKIP
  local SKIP_PROJECT=false
  local PROJECT_NAME
  local PROJECT_URL
  local CURRENT_VERSION
  local LATEST_VERSION
  local UPDATE_STATUS
  local ABANDONED
  local PATCHES
  PROJECT_NAME=$(echo "${COMPOSER_PACKAGE}" | jq '."name"' | sed "s/\"//g")
  PROJECT_URL=$(echo "${COMPOSER_PACKAGE}" | jq '."homepage"' | sed "s/\"//g")
  if [ -z "$PROJECT_URL" ] || [ "$PROJECT_URL" == null ]; then
    PROJECT_URL="https://www.drupal.org/project/drupal"
  fi
  CURRENT_VERSION=$(echo "${COMPOSER_PACKAGE}" | jq '."version"' | sed "s/\"//g")
  LATEST_VERSION=$(echo "${COMPOSER_PACKAGE}" | jq '."latest"' | sed "s/\"//g")
  UPDATE_STATUS=$(echo "${COMPOSER_PACKAGE}" | jq '."latest-status"' | sed "s/\"//g")
  ABANDONED=$(echo "${COMPOSER_PACKAGE}" | jq '."abandoned"' | sed "s/\"//g")
  PATCHES=$(echo "$COMPOSER_CONTENTS" | jq '.extra.patches."'"$PROJECT_NAME"'" | length')

  local PATCH_LIST=
  if [ "$PATCHES" -gt 0 ]; then
    PATCH_LIST=$(echo "$COMPOSER_CONTENTS" | jq '.extra.patches."'"$PROJECT_NAME"'"')
  fi

  local PROJECT_RELEASE_URL=$PROJECT_URL
  if [[ $LATEST_VERSION != dev-* ]]; then
     PROJECT_RELEASE_URL=$PROJECT_URL"/releases/"$LATEST_VERSION
  fi

      # Go through excluded packages and skip them.
  if [ -n "$UPDATE_EXCLUDE" ]; then
    local EXCLUDE=
    for EXCLUDE in $UPDATE_EXCLUDE
    do
      if [ "$PROJECT_NAME" == "drupal/$EXCLUDE" ]; then
        echo "Skipping upgrades for $PROJECT_NAME"
        SKIP_PROJECT=true
      fi
    done
  fi

  if [ "$UPDATE_TYPE" != "all" ] && [ "$UPDATE_STATUS" != "$UPDATE_TYPE" ]; then
    echo "Skipping upgrades for $PROJECT_NAME"
    SKIP_PROJECT=true
  fi

  if [ $SKIP_PROJECT == false ]; then
    echo "Update $PROJECT_NAME from $CURRENT_VERSION to $LATEST_VERSION"
    RESULT_STATUS=$(composer_output "$PROJECT_NAME" "$LATEST_VERSION" "$UPDATE_STATUS" "$PATCH_LIST")
    # Write specific cases in the highlights summary report.
    if [ ${#RESULT_STATUS} -gt 20 ]; then
      RESULT_HIGHLIGHTS+="- **$PROJECT_NAME** have failed to apply a patch: *$RESULT_STATUS*.\n"
      RESULT_STATUS=$RESULT_PATCH_FAILURE
    fi

    if [ "$RESULT_STATUS" == "$RESULT_DEPENDENCY_ERROR" ]; then
      RESULT_HIGHLIGHTS+="- **$PROJECT_NAME** have an unresolved dependency.\n"
    fi
  fi
  # Write entry for all cases.
  RESULT_TABLE+="| [${PROJECT_NAME}](${PROJECT_URL}) | ${CURRENT_VERSION} | [${LATEST_VERSION}]($PROJECT_RELEASE_URL) | $RESULT_STATUS | $PATCHES | $ABANDONED |\n"
}

# Set default values.
SUMMARY_FILE=
UPDATE_TYPE="semver-safe-update"
UPDATE_EXCLUDE=
UPDATE_CORE=true
COMPOSER_PREFIX=""

# Determine if we're running inside GitHub actions.
GITHUB_RUNNING_ACTION=$GITHUB_ACTIONS

# For GitHub actions, use inputs.
if [ "$GITHUB_RUNNING_ACTION" == true ]
then
  UPDATE_TYPE=${INPUT_UPDATE_TYPE}
  UPDATE_CORE=${INPUT_UPDATE_CORE}
  UPDATE_EXCLUDE=${INPUT_UPDATE_EXCLUDE}
  COMPOSER_PREFIX=${INPUT_COMPOSER_PREFIX}
fi

# Go through any flags available.
while getopts "h:t:c:e:o:p:" options; do
  case "${options}" in
  h)
    echo usage
    exit
    ;;
  t)
    UPDATE_TYPE=${OPTARG}
    ;;
  c)
    UPDATE_CORE=${OPTARG}
    ;;
  e)
    UPDATE_EXCLUDE=${OPTARG}
    ;;
  o)
    SUMMARY_FILE=${OPTARG}
    ;;
  p)
    COMPOSER_PREFIX=${OPTARG}
    ;;
  :)
    echo "Error: -${OPTARG} requires an argument."
    ;;
  *)
    exit_error
    ;;
  esac
done

# Perform validations of shell script arguments and requirements to run the script.
validate_options "$UPDATE_TYPE" "$UPDATE_CORE" "$UPDATE_EXCLUDE" "$SUMMARY_FILE" "$COMPOSER_PREFIX"
validate_requirements

# If we have a list of excluded modules, convert it to a loop list.
if [ -n "$UPDATE_EXCLUDE" ]; then
  UPDATE_EXCLUDE="${UPDATE_EXCLUDE//,/ }"
fi

# Get full composer content for later usage.
COMPOSER_CONTENTS=$(< composer.json);

SUMMARY_INSTRUCTIONS="### Automated Drupal update summary\n"

# Define a variable for writing a summary table.
SUMMARY_OUTPUT_TABLE="| Project name | Old version | Proposed version | Status | Patches | Abandoned |\n"
SUMMARY_OUTPUT_TABLE+="| ------ | ------ | ------ | ------ | ------ | ------ |\n"
# Read composer output. Remove whitespaces - jq 1.5 can break while parsing.
UPDATES=$($COMPOSER_PREFIX composer outdated "drupal/*" -f json -D --locked --ignore-platform-reqs | sed -r 's/\s+//g');

# Loop trough other packages.
for UPDATE_PACKAGE in $(echo "${UPDATES}" | jq -c '.locked[]'); do
  PROJECT_NAME=$(echo "${UPDATE_PACKAGE}" | jq '."name"' | sed "s/\"//g")
  # Skip all core packages. Perform core upgrades as last one.
  if [[ "$PROJECT_NAME" = drupal/core-* ]] || [ "$PROJECT_NAME" = "drupal/core" ]; then
    continue
  fi
  update_project "$UPDATE_PACKAGE" SUMMARY_OUTPUT_TABLE SUMMARY_INSTRUCTIONS
done

# If we have core updates enabled, these needs to run last in ideal case.
# It is not going through work for 99.99% of 9.5 to 10 installations.
# It should be passable between same major versions of D10.
if [ "$UPDATE_CORE" == true ]; then
  CORE_PACKAGE=$(echo "${UPDATES}" | jq -c '.locked[] | select(.name == "drupal/core")')
  if [ -z "$CORE_PACKAGE" ] || [ "$CORE_PACKAGE" == null ]; then
    CORE_PACKAGE=$(echo "${UPDATES}" | jq -c '.locked[] | select(.name == "drupal/core-recommended")')
  fi
  if [ "$CORE_PACKAGE" ]; then
    update_project "$CORE_PACKAGE" SUMMARY_OUTPUT_TABLE SUMMARY_INSTRUCTIONS
  fi
fi

SUMMARY_INSTRUCTIONS+="\n$SUMMARY_OUTPUT_TABLE"

# For GitHub actions, use GitHub step summary and environment variable DRUPAL_UPDATES_TABLE.
if [ "$GITHUB_RUNNING_ACTION" == true ]; then
  echo -e "$SUMMARY_INSTRUCTIONS" >> "$GITHUB_STEP_SUMMARY"
  {
    echo 'DRUPAL_UPDATES_TABLE<<EOF'
    cat "$GITHUB_STEP_SUMMARY"
    echo 'EOF'
  } >>"$GITHUB_ENV"
else
  echo -e "$SUMMARY_INSTRUCTIONS"
fi

# If we have a summary file.
if [ -n "$SUMMARY_FILE" ]; then
  if [ ! -f "$SUMMARY_FILE" ]; then
    touch "$SUMMARY_FILE"
  fi
  echo -e "$SUMMARY_INSTRUCTIONS" > "$SUMMARY_FILE"
fi