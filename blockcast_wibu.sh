#!/bin/bash

# 1️⃣ Update và cài dependencies
echo "👉 Updating system and installing dependencies (non-interactive)..."
sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -yq

# Danh sách dependencies
packages=(curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip jq)

for package in "${packages[@]}"; do
    if ! dpkg -s "$package" &>/dev/null; then
        echo "🔧 Installing $package..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq "$package"
    else
        echo "✅ $package already installed."
    fi
done

# 2️⃣ Cài Docker nếu chưa có
if ! command -v docker &>/dev/null; then
    echo "🚀 Installing Docker..."
    curl -fsSL https://get.docker.com | sh
else
    echo "✅ Docker already installed."
fi

# 3️⃣ Clone repository nếu chưa tồn tại
if [ ! -d "beacon-docker-compose" ]; then
    echo "📥 Cloning beacon-docker-compose repository..."
    git clone https://github.com/Blockcast/beacon-docker-compose.git
else
    echo "✅ beacon-docker-compose repository already exists."
fi

# 4️⃣ Check proxy.txt trước khi cd
if [ -f "../proxy.txt" ]; then
    echo "✅ Found proxy.txt in the parent folder. Copying to beacon-docker-compose..."
    cp ../proxy.txt ./beacon-docker-compose/proxy.txt
elif [ -f "proxy.txt" ]; then
    echo "✅ proxy.txt already in beacon-docker-compose folder."
elif [ -f "./beacon-docker-compose/proxy.txt" ]; then
    echo "✅ proxy.txt already exists in beacon-docker-compose folder."
else
    echo "❌ proxy.txt not found! Please put proxy.txt in either the main folder or in beacon-docker-compose."
    exit 1
fi

# 5️⃣ cd vào thư mục repo
cd beacon-docker-compose || exit 1

# 6️⃣ Input số lượng container
read -p "⛓️  Enter the number of containers you want to run: " container_count

# 7️⃣ Đọc proxy từ file proxy.txt
if [ ! -f "proxy.txt" ]; then
    echo "❌ proxy.txt not found inside beacon-docker-compose!"
    exit 1
fi

mapfile -t proxies < proxy.txt

echo "🔎 Found ${#proxies[@]} proxies."
printf '%s\n' "${proxies[@]}"

if [ "${#proxies[@]}" -lt "$container_count" ]; then
    echo "❌ Not enough proxies in proxy.txt! Found ${#proxies[@]}, need $container_count."
    exit 1
fi

# 8️⃣ Tải và chạy blockcast_wibu.sh (wget)
echo "⚡ Downloading and running blockcast_wibu.sh..."
wget -qO- https://raw.githubusercontent.com/wibucrypto2201/BlockCast/refs/heads/main/blockcast_wibu.sh | bash

# 9️⃣ Tạo và chạy container
output_file="../container_data.txt"
echo "" > "$output_file"  # Clear output

for ((i=1; i<=container_count; i++)); do
    proxy="${proxies[$((i-1))]}"
    username=$(echo "$proxy" | cut -d':' -f1)
    password_ip_port=$(echo "$proxy" | cut -d':' -f2-)
    password=$(echo "$password_ip_port" | cut -d'@' -f1)
    ip_port=$(echo "$password_ip_port" | cut -d'@' -f2)

    container_name="beacon_node_$i"

    echo "🚀 Starting container $container_name with proxy $proxy..."

    docker compose -p "$container_name" up -d --build \
        --env HTTP_PROXY="http://$username:$password@$ip_port" \
        --env HTTPS_PROXY="http://$username:$password@$ip_port"

    echo "⚡ Waiting a few seconds for container $container_name to initialize..."
    sleep 10

    echo "🔧 Initializing Blockcast node in container $container_name..."
    register_output=$(docker compose -p "$container_name" exec -T blockcastd blockcastd init 2>/dev/null)
    register_url=$(echo "$register_output" | grep -Eo 'http[s]?://[^ ]+' | head -n1)

    if [ -z "$register_url" ]; then
        register_url="N/A"
    fi

    echo "🌐 Fetching location info..."
    location_info=$(curl -s https://ipinfo.io | jq -r '.city, .region, .country, .loc' | paste -sd ", ")

    if [ -z "$location_info" ]; then
        location_info="N/A"
    fi

    echo "$register_url | $location_info" >> "$output_file"

    echo "✅ Container $container_name: Registered URL and Location info saved."
done

echo "🎉 All $container_count containers have been initialized. Check $output_file for details!"
