#!/usr/bin/env bash

RUBY_VERSION="2.1.2"
NODE_VERSION="0.10.33"

RUNTIME_PACKAGES="
  zlib1g
  libssl1.0.0
  libreadline6
  libyaml-0-2
  sqlite3
  libxml2
  libxslt1.1
  libcurl3
"

COMPILER_PACKAGES="
  unzip
  git
  git-core
  curl
  zlib1g-dev
  build-essential
  libssl-dev
  libreadline-dev
  libyaml-dev
  libsqlite3-dev
  sqlite3
  libxml2-dev
  libxslt1-dev
  libcurl4-openssl-dev
  python-software-properties
"

function run() {
  # create cache directory if missing
  if [[ ! -d "${cachedir}" ]]; then
    mkdir -p ${cachedir}
  fi

  # clean any old code
  clean

  app_base_container_exists || build_app_base_container
  ruby_compiler_base_container_exists || build_ruby_compiler_base_container

  # fetch the new app code
  # get_app_source
  # build_compiler_image
  # build_runtime_image
  # archive
}

function app_base_container_exists() {
  test -n "$(docker images | grep '^app-base ')"
}

function build_app_base_container() {
  debug "building application base container"
  mkdir -p "${cachedir}/app-base"
  tee "${cachedir}/app-base/Dockerfile" > /dev/null <<EOF
Pull the latest canonical ubuntu image
FROM ubuntu

ENV RUBY_VERSION ${RUBY_VERSION}
ENV NODE_VERSION ${NODE_VERSION}
ENV GEM_PATH /app/vendor/bundle

# Set the app, gem, ruby
# and node executables in the path
ENV PATH /app/bin:/app/vendor/bundle/bin:/app/vendor/ruby/${RUBY_VERSION}/bin:/app/vendor/node/${NODE_VERSION}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF
  docker build --tag app-base ${cachedir}/app-base &>> ${logfile}
}

function clean() {
  if [[  -d "${cachedir}/app" ]]; then
    rm -rf ${cachedir}/app
  fi
}

function get_app_source() {
  info "fetching application source"
  git clone ${repo} ${cachedir}/app --depth 1 2>> ${logfile}
  log "successfully cloned source to ${cachedir}/app"
}


function ruby_compiler_base_container_exists() {
  test -n "$(docker images | grep '^ruby-compiler-base ')"
}

function build_ruby_compiler_base_container {
  debug "building base ruby compiler container"
  local dir="${cachedir}/ruby-compiler-base"
  local pkgs=$(printf "%s " $COMPILER_PACKAGES)

  mkdir -p ${dir}
  cat > "${dir}/Dockerfile" <<EOF
FROM app-base
RUN apt-get update && apt-get install -y ${pkgs}

# Create the application directory
# where all the app's dependencies will be placed
RUN mkdir -p /app

# Install and build ruby in the app directory
RUN git clone https://github.com/sstephenson/ruby-build.git /ruby-build
RUN /ruby-build/bin/ruby-build ${RUBY_VERSION} /app/vendor/ruby/${RUBY_VERSION}

# Install nodejs binaries
RUN curl http://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.gz | tar xz
RUN mkdir -p /app/vendor/node/${NODE_VERSION}
RUN mv node-v${NODE_VERSION}-linux-x64/* /app/vendor/node/${NODE_VERSION}

# Install and update rubygems and install bundler
RUN gem install rubygems-update bundler --no-ri --no-rdoc
RUN update_rubygems
EOF
  docker build --tag ruby-compiler-base ${dir} &>> ${logfile}
}


function build_base_runtime_container() {
 echo "hi"
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
  debug "building compiler image using ${cachedir}/Dockerfile"
  docker build --tag app-compiler $cachedir &>> ${logfile}

  local id=$(docker run -dt app-compiler /bin/bash)
  mkdir -p ${cachedir}/runtime
  docker cp ${id}:/app ${cachedir}/runtime
  debug "application compiled to ${cachedir}/runtime"
  docker rm --force ${id} > /dev/null
  debug "removing compiler copy container ${id}"
}

function build_runtime_image() {
 local secretsbase=$(date +%s | sha256sum | base64 | head -c 64)
 local pkgs=$(printf "%s " $RUNTIME_PACKAGES)
 mkdir -p ${cachedir}/runtime
 tee "${cachedir}/runtime/Dockerfile" > /dev/null <<EOF
FROM ubuntu
RUN apt-get update && apt-get install -y ${pkgs}
ENV RAILS_ENV production
ENV SECRET_KEY_BASE ${secretsbase}
ADD app app
WORKDIR app
EOF
  debug "building runtime image using ${cachedir}/runtime/Dockerfile"
  docker build --tag app ${cachedir}/runtime &>> ${logfile}
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
