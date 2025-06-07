#!/bin/bash

# Clone repo nếu chưa clone
if [ ! -d beacon-docker-compose ]; then
    git clone https://github.com/wibucrypto2201/beacon-docker-compose.git
fi

cd beacon-docker-compose || exit 1

# Pull latest image
docker compose pull

# Khởi chạy từng proxy
instance_id=1
while IFS= read -r proxy_line; do
    export INSTANCE_ID=$instance_id
    export PROXY_AUTH=$proxy_line
    export PROXY_PORT=$((8080 + instance_id))

    echo "Starting container_${instance_id} with proxy: ${proxy_line} on port ${PROXY_PORT}"

    INSTANCE_ID=$instance_id \
    PROXY_AUTH=$proxy_line \
    PROXY_PORT=$((8080 + instance_id)) \
    docker compose up -d

    ((instance_id++))
done < proxy.txt

echo "Tất cả container đã khởi chạy!"
