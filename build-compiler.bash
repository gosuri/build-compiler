#!/usr/bin/env bash

function run() {
  # create cache directory if missing
  if [[ ! -d "${cachedir}" ]]; then
    mkdir -p ${cachedir}
  fi

  # clean any old code
  clean

  # fetch the new app code
  get_app_source
  build_docker_image
  # archive
}

function clean() {
  if [[  -d "${cachedir}/app" ]]; then
    rm -rf ${cachedir}/app
  fi
}

function get_app_source() {
  git clone ${repo} ${cachedir}/app --depth 1
}

function build_docker_image() {
  local image="app-base"
  tee "${cachedir}/Dockerfile" > /dev/null <<EOF
FROM ${image}
ADD app app
ENV RAILS_ENV production
RUN bundle install --path=vendor/bundle --binstubs vendor/bundle/bin  --jobs=4 --retry=3
RUN bundle exec rake assets:precompile
EOF
  docker build --tag app-compiler $cachedir
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

function init() {
  if [[ -z "${cachedir}" ]]; then
    cachedir=${TMPDIR}/build-compiler-$$.$RANDOM
  fi
  bash_sugar_init || exit 2
}

repo=${1}
cachedir=${2}

init
validate
run
