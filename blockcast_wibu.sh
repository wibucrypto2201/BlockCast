#!/bin/bash
set -e

# === Bước 1: Cập nhật hệ thống ===
sudo apt-get update && sudo apt-get upgrade -y

# === Bước 2: Cài đặt các gói cần thiết ===
sudo apt install -y \
    curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop \
    nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip

# === Bước 3: Gỡ bỏ các gói Docker cũ ===
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    sudo apt-get remove -y $pkg
done

# === Bước 4: Cài đặt Docker chính thức ===
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# === Bước 5: Kiểm tra Docker ===
sudo docker run hello-world
sudo systemctl enable docker
sudo systemctl restart docker

# === Bước 6: Clone Blockcast repository ===
git clone https://github.com/Blockcast/beacon-docker-compose.git
cd beacon-docker-compose

# === Bước 7: Kéo image mới nhất ===
docker compose pull

# === Bước 8: Xử lý proxy.txt và khởi tạo containers ===
counter=1
rm -f ../container_data.txt

while IFS= read -r proxy_line || [[ -n "$proxy_line" ]]; do
    username=$(echo "$proxy_line" | cut -d':' -f1)
    pass_ip_port=$(echo "$proxy_line" | cut -d':' -f2-)
    password=$(echo "$pass_ip_port" | cut -d'@' -f1)
    ip_port=$(echo "$pass_ip_port" | cut -d'@' -f2)
    ip=$(echo "$ip_port" | cut -d':' -f1)
    port=$(echo "$ip_port" | cut -d':' -f2)

    container_name="blockcastd_$counter"

    echo "=============================="
    echo "Khởi tạo container: $container_name"
    echo "Proxy: $username:$password@$ip:$port"
    echo "=============================="

    # === Bước 8.1: Tạo container mới với proxy ===
    docker compose run -d \
        --name $container_name \
        -e HTTP_PROXY="http://$username:$password@$ip:$port" \
        -e HTTPS_PROXY="http://$username:$password@$ip:$port" \
        blockcastd

    # === Bước 8.2: blockcastd init ===
    docker compose exec $container_name blockcastd init

    # === Bước 8.3: Lấy thông tin location thông qua proxy ===
    location=$(docker compose exec $container_name \
        curl -x http://$username:$password@$ip:$port -s https://ipinfo.io | \
        jq -r '.city, .region, .country, .loc' | paste -sd "," -)

    # === Bước 8.4: Ghi dữ liệu container vào file container_data.txt ===
    echo "$container_name|$proxy_line|$location" >> ../container_data.txt

    counter=$((counter + 1))
done < ../proxy.txt

echo "=============================="
echo "Tất cả containers đã được khởi chạy."
echo "Thông tin được lưu trong container_data.txt"
