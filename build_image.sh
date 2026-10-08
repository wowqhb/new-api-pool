#!/bin/bash

default_version=$1
if [[ "${default_version}" == "" ]]; then
	default_version=$(date +"%Y%m%d-%H%M%S-%3N")
fi
cp -r docker-compose.yaml.template docker-compose.yaml
sed -i "s/{{version}}/${default_version}/g" docker-compose.yaml
docker compose build --no-cache
echo "Image version: ${default_version}"
