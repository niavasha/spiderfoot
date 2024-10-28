#!/bin/bash -e
build_date=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
build_day=$(date -u +'%Y-%m-%d')
git pull
#docker build --rm --no-cache --build-arg BUILD_DATE=$build_date \
docker build --build-arg BUILD_DATE=$build_date \
    -t niavasha/spiderfoot -f Dockerfile .
docker tag niavasha/spiderfoot:latest niavasha/spiderfoot:$build_day
docker push niavasha/spiderfoot
docker pull niavasha/spiderfoot
