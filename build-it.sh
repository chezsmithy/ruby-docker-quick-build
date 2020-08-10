#!/bin/sh

echo "building base image"
# Notice we will build for local, development mode not Production here
# By default, don't specify a target and the default build stage
# will be production
# Docker image inspect is checking if a previous build exists on the image
# If it does, then accelerate the build by copying the bundle cache from it
docker image inspect my_image_base:latest >/dev/null 2>&1 && \
  time docker build -t my_image_base:latest --target local --build-arg BUNDLE_TYPE=accelerated -f Dockerfile . \
  || time docker build -t my_image_base:latest --target local --build-arg BUNDLE_TYPE=gemfile -f Dockerfile .
echo "building docker compose"
time docker-compose -f docker-compose.yml build