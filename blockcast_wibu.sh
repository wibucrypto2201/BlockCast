#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "👉 Updating system and installing dependencies..."
sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -yq

packages=(curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip jq)
for package in "${packages[@]}"; do
    if ! dpkg -s "$package" &>/dev/null; then
        echo "🔧 Installing $package..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq "$package"
    else
        echo "✅ $package already installed."
    fi
done

if ! command -v docker &>/dev/null; then
    echo "🚀 Installing Docker..."
    curl -fsSL https://get.docker.com | sh
else
    echo "✅ Docker already installed."
fi

if [ ! -d "$SCRIPT_DIR/beacon-docker-compose" ]; then
    echo "📥 Cloning beacon-docker-compose repository..."
    git clone https://github.com/Blockcast/beacon-docker-compose.git "$SCRIPT_DIR/beacon-docker-compose"
else
    echo "✅ beacon-docker-compose repository already exists."
fi

if [ -f "$SCRIPT_DIR/proxy.txt" ]; then
    echo "✅ Found proxy.txt in the script folder."
else
    echo "❌ proxy.txt not found! Please create proxy.txt with format user:pass@ip:port (1 per line)."
    exit 1
fi

mapfile -t proxies < "$SCRIPT_DIR/proxy.txt"
echo "🔎 Found ${#proxies[@]} proxies."
printf '%s\n' "${proxies[@]}"

read -p "⛓️  Enter the number of containers you want to run: " container_count
if [ "${#proxies[@]}" -lt "$container_count" ]; then
    echo "❌ Not enough proxies! Found ${#proxies[@]}, need $container_count."
    exit 1
fi

cd "$SCRIPT_DIR/beacon-docker-compose" || exit 1

if grep -q 'container_name:' docker-compose.yml; then
    echo "⚡ Removing all 'container_name:' entries..."
    sed -i '/container_name:/d' docker-compose.yml
fi

output_file="$SCRIPT_DIR/container_data.txt"
echo "" > "$output_file"

for ((i=1; i<=container_count; i++)); do
    proxy="${proxies[$((i-1))]}"
    username=$(echo "$proxy" | cut -d':' -f1)
    password_ip_port=$(echo "$proxy" | cut -d':' -f2-)
    password=$(echo "$password_ip_port" | cut -d'@' -f1)
    ip_port=$(echo "$password_ip_port" | cut -d'@' -f2)

    container_name="beacon_node_$i"
    override_file="docker-compose.override.yml"

    echo "⚡ Generating docker-compose.override.yml for $container_name..."
    cat > "$override_file" <<EOF
services:
  blockcastd:
    environment:
      - http_proxy=http://$username:$password@$ip_port
      - https_proxy=http://$username:$password@$ip_port
  tinyproxy:
    image: vimagick/tinyproxy
    environment:
      - PROXY_USER=$username
      - PROXY_PASS=$password
    ports:
      - "8888"
EOF

    echo "🚀 Starting container $container_name with proxy $proxy..."
    docker compose -p "$container_name" up -d --build

    echo "⚡ Waiting a few seconds for container $container_name to initialize..."
    sleep 10

    echo "🔧 Initializing Blockcast node in container $container_name..."
    register_output=$(docker compose -p "$container_name" exec -T blockcastd blockcastd init 2>/dev/null)
    register_url=$(echo "$register_output" | grep -Eo 'http[s]?://[^ ]+' | head -n1)
    if [ -z "$register_url" ]; then register_url="N/A"; fi

    echo "🌐 Fetching IP info from container $container_name using proxy..."
    location_info=$(docker compose -p "$container_name" exec -T blockcastd curl -x "http://$username:$password@$ip_port" -s https://ipinfo.io | \
        jq -r '.city, .region, .country, .loc' | paste -sd ", ")
    if [ -z "$location_info" ]; then location_info="N/A"; fi

    echo "$register_url | $location_info" >> "$output_file"
    echo "✅ Container $container_name done."
done

echo "🎉 All containers initialized. Check $output_file for results!"
