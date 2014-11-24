#!/usr/bin/env bash

RUNTIME_PACKAGES=""

function run() {
  # create cache directory if missing
  if [[ ! -d "${cachedir}" ]]; then
    mkdir -p ${cachedir}
  fi

  # clean any old code
  clean

  # fetch the new app code
  get_app_source
  build_compiler_image
  # archive
}

function clean() {
  if [[  -d "${cachedir}/app" ]]; then
    rm -rf ${cachedir}/app
  fi
}

function get_app_source() {
  info "fetching application source"
  git clone ${repo} ${cachedir}/app --depth 1 2> ${logfile}
  log "successfully cloned source to ${cachedir}/app"
}

function build_compiler_image() {
  info "compiling application"
  local image="app-base"
  tee "${cachedir}/Dockerfile" > /dev/null <<EOF
FROM ${image}
ADD app app
ENV RAILS_ENV production
RUN bundle install --path=vendor/bundle --binstubs vendor/bundle/bin  --jobs=4 --retry=3
RUN bundle exec rake assets:precompile
EOF
  log "building compiler image using ${cachedir}/Dockerfile"
  docker build --tag app-compiler $cachedir &> ${logfile}

  local id=$(docker run -dt app-compiler /bin/bash)
  docker cp ${id}:/app compiled
  debug "application compiled to ${cachedir}/compiled"
  debug "removing compiler container"
  docker --force rm ${id} 
}

function build_runtime_image() {
 cat > "${cachedir}/runtimeimage" <<EOF
FROM ubuntu
ENV RAILS_ENV production
ADD app app
EOF
}

function help() {
  echo -e "usage: ${0} GIT_REPO [CACHE_DIR]"
}

function validate() {
  abort_if_missing_command git "git is required to run ${0}. Install using sudo apt-get install git"

  if [[ -z "${repo}" ]]; then
    echo $(help)
    abort "\nerror: app source is missing"
  fi
}

function info() {
  local msg="==> build-compiler: ${*}"
  echo -e "${msg}" >> ${logfile}
  echo_info "${msg}"
}

function log() {
  local msg="                    ${*}"
  echo -e "${msg}"
  echo -e "${msg}" >> ${logfile}
}

function debug() {
  [ "${DEBUG}" == "true" ] && log ${*}
}

function init() {
  debug "using logfile ${logfile}"
  if [[ -z "${cachedir}" ]]; then
    cachedir=$(mktemp -d --tmpdir $TMPDIR build-compiler-XXXXXXX)
  fi
  debug "using cache directory ${cachedir}"
  bash_sugar_init || exit 2
}

repo=${1}
cachedir=${2}
logfile=$(mktemp --tmpdir $TMPDIR build-compiler-XXXXXXX.log)

if [ -z "${DEBUG}" ]; then
  DEBUG=false
fi

init
validate
run
