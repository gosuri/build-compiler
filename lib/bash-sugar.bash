#!/usr/bin/env bash

# Provides various bash helpers

function bash_sugar_init() {
  # Will exit script if we would use an uninitialised variable:
  set -o nounset

  # Will exit script when a simple command (not a control structure) fails:
  set -o errexit
}

# abort ...
#
# Abort and writes the message in red to standard error
#
function abort() {
  local red=$(tput setaf 1)
  local reset=$(tput sgr0)
  echo >&2 -e "${red}$@${reset}"
  exit 1
}

# abort_if_command_missing "cmd" "msg"
#
# Aborts the given command is missing
#
function abort_if_missing_command() {
  local cmd=$1
  type ${cmd} >/dev/null 2>&1 || abort "${2}"
}

# abort_if_file_missing "file" "msg"
#
# Aborts if file is missing 
#
function abort_if_file_missing() { 
  local file=${1}
  if [[ ! -f "${file}" ]]; then
    abort "${2}"
  fi
}

# abort_if_not_root "msg"
#
# Aborts if the current user is not root
#
function abort_if_not_root() {
  if [[ ${EUID} -ne 0 ]]; then
    abort "${1}"
  fi
}

# abort_if_var_missing $VAR "msg" 
# 
# Aborts if the environment variable is missing
function abort_if_var_missing() {
  if [[ -z "${1}" ]]; then
    abort "${2}"
  fi
}

# echo_info message ...
#
# Writes the message in bold to standard out
#
function echo_info() {
  local bold=$(tput bold)
  local reset=$(tput sgr0)
  echo -e "${bold}$@${reset}"
}

# echo_warn message ...
#
# Writes the message in yellow to standard out
#
function echo_warn() {
  local yellow=$(tput setaf 3)
  local reset=$(tput sgr0)
  echo -e "${yellow}$@${reset}"
}
