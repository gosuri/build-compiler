#!/usr/bin/env bash

RUBY_VERSION="2.1.2"
NODE_VERSION="0.10.33"

# Minimal set of packages necessary for running the application
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

# Packages required to compile(install ruby and gems) the application
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

  # build base container image if it doesn't exit
  app_base_container_exists           || build_app_base_container
  
  # build base ruby container image with compilers if it doesn't exit
  ruby_compiler_base_container_exists || build_ruby_compiler_base_container
  
  # build base application compiler image with compilers if it doesn't exit
  app_compiler_container_exists       || build_app_compiler_container

  # fetch the new app code
  get_app_source
  
  # compile application
  compile_app

  # copy compiled application with all dependencies
  copy_compiled_app
 
  # build base runtime container if it doesnt exists
  app_runtime_container_exists       || build_app_runtime_container

  # build runtime image
  build_runtime_image
 
  # clean up the logfile and temp directory
  clean
}

function app_base_container_exists() {
  test -n "$(docker images | grep '^app-base ')"
}

function build_app_base_container() {
  log "building application base container"
  mkdir -p "${cachedir}/app-base"
  tee "${cachedir}/app-base/Dockerfile" > /dev/null <<EOF
# Pull the latest canonical ubuntu image
FROM ubuntu

ENV RUBY_VERSION ${RUBY_VERSION}
ENV NODE_VERSION ${NODE_VERSION}
ENV GEM_PATH /app/vendor/bundle

# Set the app, gem, ruby
# and node executables in the path
ENV PATH /app/bin:/app/vendor/bundle/bin:/app/vendor/ruby/${RUBY_VERSION}/bin:/app/vendor/node/${NODE_VERSION}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF
  docker build --tag app-base ${cachedir}/app-base >> ${logfile} 2>&1
}

function clean() {
  if [[  -d "${cachedir}" ]]; then
    rm -rf ${cachedir}/*
  fi
  rm -f $logfile
}

function get_app_source() {
  info "fetching application source"
  git clone ${repo} ${cachedir}/app-compiler/app --depth 1 >> ${logfile} 2>&1
  log "successfully cloned source to ${cachedir}/app-compiler/app"
}

function ruby_compiler_base_container_exists() {
  test -n "$(docker images | grep '^ruby-compiler-base ')"
}

function build_ruby_compiler_base_container {
  log "building base ruby compiler container"
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
  docker build --tag ruby-compiler-base ${dir} >> ${logfile} 2>&1
}

function app_compiler_container_exists() {
  test -n "$(docker images | grep '^app-compiler ')"
}

function build_app_compiler_container() {
  log "building app-compiler container"
  local dir="${cachedir}/app-compiler"
  mkdir -p ${dir}
  echo "FROM ruby-compiler-base" > "${dir}/Dockerfile"
  docker build --tag app-compiler ${dir} >> ${logfile} 2>&1
}

function compile_app() {
  info "compiling application"
  local dir="${cachedir}/app-compiler"
  mkdir -p ${dir}
  cat > "${dir}/Dockerfile" <<EOF
FROM app-compiler
ADD app app
ENV RAILS_ENV production
WORKDIR /app
RUN bundle install --path=vendor/bundle --binstubs vendor/bundle/bin  --jobs=4 --retry=3
RUN bundle exec rake assets:precompile
EOF
  docker build --tag app-compiler $dir >> ${logfile} 2>&1
}

function copy_compiled_app() {
  local id=$(docker run -dt app-compiler /bin/bash)
  local dir=${cachedir}/app-runtime
  mkdir -p ${dir}
  docker cp ${id}:/app ${dir}
  log "application compiled to ${dir}"
  docker rm --force ${id} > /dev/null
  log "removing compiler copy container ${id}"
}

function build_compiler_image() {
  info "compiling application"
  local image="app-base"
  tee "${cachedir}/Dockerfile" > /dev/null <<EOF
FROM app-compiler
ADD app app
ENV RAILS_ENV production
RUN bundle install --path=vendor/bundle --binstubs vendor/bundle/bin  --jobs=4 --retry=3
RUN bundle exec rake assets:precompile
EOF
  log "building compiler image using ${cachedir}/Dockerfile"
  docker build --tag app-compiler $cachedir >> ${logfile} 2>&1
}

function app_runtime_container_exists() {
  test -n "$(docker images | grep '^app-runtime ')"
}

function build_app_runtime_container() {
 log "building app runtime base container"
 local secretsbase=$(date +%s | sha256sum | base64 | head -c 64)
 local pkgs=$(printf "%s " $RUNTIME_PACKAGES)
 local dir="${cachedir}/app-runtime"
 tee "${dir}/Dockerfile" > /dev/null <<EOF
FROM app-base
RUN apt-get update && apt-get install -y ${pkgs}
ENV RAILS_ENV production
ENV SECRET_KEY_BASE ${secretsbase}
RUN mkdir -p /app
EOF
  docker build --tag app-runtime ${dir} >> ${logfile} 2>&1
}

function build_runtime_image() {
  info "building app-runtime container image"
  dir="${cachedir}/app-runtime"
  mkdir -p ${dir}
  cat > ${dir}/Dockerfile <<EOF
FROM app-runtime
ADD app app
WORKDIR /app
EOF
  docker build --tag app-runtime ${dir} >> ${logfile} 2>&1
  info "application successfully built"
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
  local msg="${*}"
  if [ "${DEBUG}" == "true" ]; then
    echo -e "[debug] ${msg}"
  fi
  echo -e "${msg}" >> ${logfile}
}

function init() {
  log "using logfile ${logfile}"
  if [[ -z "${cachedir}" ]]; then
    cachedir=$(mktemp -d --tmpdir $TMPDIR build-compiler-XXXXXXX)
  fi
  log "using cache directory ${cachedir}"
  logfile="${cachedir}/log"
  bash_sugar_init || exit 2
}

repo=${1}
cachedir=${2}
logfile="${cachedir}/log"

if [ -z "${DEBUG}" ]; then
  DEBUG=false
fi

init
validate
run
