#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2017-2020, Intel Corporation

#
# build-local.sh - runs a Docker container from a Docker image with environment
#                  prepared for running libpmemobj-cpp tests and run those tests.
#
#
# Notes:
# - run this script from its location or set the variable 'HOST_WORKDIR' to
#   where the root of this project is on the host machine,
# - set variables 'OS' and 'OS_VER' properly to a system you want to build this
#	repo on (for proper values take a look on the list of Dockerfiles at the
#   utils/docker/images directory), e.g. OS=ubuntu, OS_VER=19.04.
#

set -e

# Environment variables that can be customized (default values are after dash):
export KEEP_CONTAINER=${KEEP_CONTAINER:-0}


if [[ -z "$OS" || -z "$OS_VER" ]]; then
	echo "ERROR: The variables OS and OS_VER have to be set " \
		"(e.g. OS=ubuntu, OS_VER=19.04)."
	exit 1
fi

if [[ -z "$HOST_WORKDIR" ]]; then
	HOST_WORKDIR=$(readlink -f ../..)
fi

if [[ "$TRAVIS_EVENT_TYPE" == "cron" || "$TRAVIS_BRANCH" == "coverity_scan" ]]; then
	if [[ "$TYPE" != "coverity" ]]; then
		echo "Skipping non-Coverity job for cron/Coverity build"
		exit 0
	fi
else
	if [[ "$TYPE" == "coverity" ]]; then
		echo "Skipping Coverity job for non cron/Coverity build"
		exit 0
	fi
fi

imageName=${DOCKERHUB_REPO}:1.10-${OS}-${OS_VER}
containerName=libpmemobj-cpp-${OS}-${OS_VER}

if [[ "$command" == "" ]]; then
	case $TYPE in
	debug|coverage)
		[ "$TYPE" == "coverage" ] && COVERAGE=1
		builds=(tests_gcc_debug_cpp14_no_valgrind
				tests_clang_debug_cpp17_no_valgrind)
		command="./run-build.sh ${builds[@]}";
		;;
	release)
		builds=(tests_gcc_release_cpp17_no_valgrind
				tests_clang_release_cpp11_no_valgrind)
		command="./run-build.sh ${builds[@]}";
		;;
	valgrind)
		builds=(tests_gcc_debug_cpp14_valgrind_other)
		command="./run-build.sh ${builds[@]}";
		;;
	memcheck_drd)
		builds=(tests_gcc_debug_cpp14_valgrind_memcheck_drd)
		command="./run-build.sh ${builds[@]}";
		;;
	package)
		builds=(tests_package
			tests_findLIBPMEMOBJ_cmake)
		command="./run-build.sh ${builds[@]}";
		;;
	coverity)
		command="./run-coverity.sh";
		;;
	esac
fi

if [ "$COVERAGE" == "1" ]; then
	docker_opts="${docker_opts} `bash <(curl -s https://codecov.io/env)`";
fi

if [ -n "$DNS_SERVER" ]; then DNS_SETTING=" --dns=$DNS_SERVER "; fi

# Only run doc update on pmem/libpmemobj-cpp master branch
if [[ "$TRAVIS_BRANCH" != "master" || "$TRAVIS_PULL_REQUEST" != "false" || "$TRAVIS_REPO_SLUG" != "${GITHUB_REPO}" ]]; then
	AUTO_DOC_UPDATE=0
fi

WORKDIR=/libpmemobj-cpp
SCRIPTSDIR=$WORKDIR/utils/docker

# check if we are running on a CI (Travis or GitHub Actions)
[ -n "$GITHUB_ACTIONS" -o -n "$TRAVIS" ] && CI_RUN="YES" || CI_RUN="NO"

# do not allocate a pseudo-TTY if we are running on GitHub Actions
[ ! $GITHUB_ACTIONS ] && TTY='-t' || TTY=''

echo Building ${OS}-${OS_VER}

# Run a container with
#  - environment variables set (--env)
#  - host directory containing source mounted (-v)
#  - working directory set (-w)
docker run --privileged=true --name=$containerName -i $TTY \
	$DNS_SETTING \
	${docker_opts} \
	--env http_proxy=$http_proxy \
	--env https_proxy=$https_proxy \
	--env AUTO_DOC_UPDATE=$AUTO_DOC_UPDATE \
	--env GITHUB_TOKEN=$GITHUB_TOKEN \
	--env WORKDIR=$WORKDIR \
	--env SCRIPTSDIR=$SCRIPTSDIR \
	--env TRAVIS_REPO_SLUG=$TRAVIS_REPO_SLUG \
	--env TRAVIS_BRANCH=$TRAVIS_BRANCH \
	--env TRAVIS_EVENT_TYPE=$TRAVIS_EVENT_TYPE \
	--env COVERITY_SCAN_TOKEN=$COVERITY_SCAN_TOKEN \
	--env COVERITY_SCAN_NOTIFICATION_EMAIL=$COVERITY_SCAN_NOTIFICATION_EMAIL \
	--env COVERAGE=$COVERAGE \
	--env CHECK_CPP_STYLE=${CHECK_CPP_STYLE:-ON} \
	--env TESTS_LONG=${TESTS_LONG:-OFF} \
	--env TESTS_TBB=${TESTS_TBB:-ON} \
	--env CI_RUN=$CI_RUN \
	--env TZ='Europe/Warsaw' \
	-v $HOST_WORKDIR:$WORKDIR \
	-v /etc/localtime:/etc/localtime \
	-w $SCRIPTSDIR \
	$imageName $command
