#!/usr/bin/env bash

set -eo pipefail

circleci_docker_login () {
    docker login -u "${docker_username}" -p "${docker_password}" "${docker_registry}"
}

circleci_services_up () {
    cat <<EOF | docker-compose -p build -f - up -d
version: '2.1'
services:
  mongodb:
    image: 'mongo:3.4'
    container_name: mongodb
EOF
    docker run --rm --network build_default jwilder/dockerize dockerize \
        -wait tcp://mongodb:27017 \
        -timeout 1m
}

circleci_clean () {
    # this first step is only temporary. it assumes we're in an alpine environment without
    # the full version of `sort` which is true at time of writing.
    apk --no-cache --no-progress add coreutils

    local -r max=${1:-10}
    local -r sorted=$(docker images --format '{{.Tag}}' | grep 'build-\d\+' | sort -Vr)
    local -r newest=$(echo "${sorted}" | head -n ${max})
    local -r oldest=$(comm -2 -3 <(echo "${sorted}" | sort) <(echo "${newest}" | sort))
    for tag in $oldest; do 
        local id=$(docker images --format '{{.Tag}} {{.ID}}' | grep -w "${tag}" | awk '{print $2}')
        if [[ "${id}"  ]]; then
          echo "Deleting ${tag} [${id}]"
          docker rmi -f "${id}"
        else
          echo "Skipping ${tag}"
        fi
    done
}

circleci_docker_build () {
    circleci_clean
    local -r upstream_tag=${CIRCLE_BRANCH:-$CIRCLE_TAG}

    local args="\
        --pull \
        -t ${CIRCLE_PROJECT_REPONAME,,}:${upstream_tag//[+~]/_} \
        -t ${CIRCLE_PROJECT_REPONAME,,}:build-${CIRCLE_BUILD_NUM} \
        -t ${CIRCLE_SHA1} \
        --network container:mongodb"

    if [[ ! $(docker images --format '{{.Tag}}' | grep 'build-\d\+') ]]; then
        local -r image="${docker_registry}/${CIRCLE_PROJECT_REPONAME,,}"
        docker pull $image || true
        args="--cache-from ${image} ${args}"
    fi

    docker build $args /usr/src/app
}

circleci_docker_push () {
    local -r image="${CIRCLE_SHA1}"

    # Set the tag to the git tag if this is a tag build, or to "latest" if this is a master branch build, or the git branch name otherwise
    if [ "${CIRCLE_TAG}" ]; then tag="${CIRCLE_TAG}"; elif [ "${CIRCLE_BRANCH}" == "master" ]; then tag=latest; else tag="${CIRCLE_BRANCH}"; fi

    # Produce the final FQN of the image that we're going to push and tag the image
    readonly final="${docker_registry}/${CIRCLE_PROJECT_REPONAME,,}:${tag//[+~]/_}"
    docker tag "${image}" "${final}"

    echo "Pushing ${final}"
    docker push "${final}"
}

circleci_docker_push_maybe () {
    if [ "${CIRCLE_TAG}" ] || [ "${CIRCLE_BRANCH}" == "master" ]; then
        circleci_docker_push
    else
        echo "Skipping push of ${CIRCLE_BRANCH} image"
    fi
}
