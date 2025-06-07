#!/bin/bash
set -e

# Hàm kiểm tra và cài đặt package nếu chưa có
install_if_missing() {
    local package="$1"
    if ! dpkg -s "$package" >/dev/null 2>&1; then
        echo "Installing: $package"
        yes | sudo apt-get install -y "$package"
    else
        echo "Package already installed: $package"
    fi
}

# === Bước 1: Cập nhật hệ thống ===
yes | sudo apt-get update
yes | sudo apt-get upgrade -y

# === Bước 2: Cài đặt các gói cần thiết ===
ESSENTIAL_PACKAGES=(
    curl iptables build-essential git wget lz4 jq make gcc nano automake
    autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev
    tar clang bsdmainutils ncdu unzip
)
for pkg in "${ESSENTIAL_PACKAGES[@]}"; do
    install_if_missing "$pkg"
done

# === Bước 3: Gỡ bỏ các gói Docker cũ ===
OLD_DOCKER_PACKAGES=(docker.io docker-doc docker-compose podman-docker containerd runc)
for pkg in "${OLD_DOCKER_PACKAGES[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        echo "Removing old Docker package: $pkg"
        yes | sudo apt-get remove -y "$pkg"
    fi
done

# === Bước 4: Cài đặt Docker chính thức ===
yes | sudo apt-get update
install_if_missing ca-certificates
install_if_missing curl
install_if_missing gnupg

sudo install -m 0755 -d /etc/apt/keyrings

# Tự động overwrite file docker.gpg nếu có
if [ -f /etc/apt/keyrings/docker.gpg ]; then
    echo "Overwriting /etc/apt/keyrings/docker.gpg"
    yes | sudo rm -f /etc/apt/keyrings/docker.gpg
fi

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

yes | sudo apt-get update
yes | sudo apt-get upgrade -y

DOCKER_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
for pkg in "${DOCKER_PACKAGES[@]}"; do
    install_if_missing "$pkg"
done

# === Bước 5: Kiểm tra Docker ===
sudo docker run hello-world || true
sudo systemctl enable docker
sudo systemctl restart docker

# === Bước 6: Clone Blockcast repository ===
if [ ! -d beacon-docker-compose ]; then
    git clone https://github.com/Blockcast/beacon-docker-compose.git
fi
cd beacon-docker-compose

# === Bước 7: Kéo image mới nhất ===
docker compose pull

# === Bước 8: Hỏi số lượng container cần chạy ===
read -p "Nhập số lượng container cần chạy (hoặc Enter để chạy toàn bộ proxy.txt): " max_containers
max_containers=${max_containers:-9999}

# === Bước 9: Xử lý proxy.txt và khởi tạo containers ===
counter=1
rm -f ../container_data.txt

while IFS= read -r proxy_line || [[ -n "$proxy_line" ]]; do
    if [ "$counter" -gt "$max_containers" ]; then
        echo "Đã chạy đủ số lượng container yêu cầu: $max_containers"
        break
    fi

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

    # === Bước 9.1: Dùng docker run thay vì docker compose exec ===
    # Khởi động container
    docker run -d \
        --name $container_name \
        -e HTTP_PROXY="http://$username:$password@$ip:$port" \
        -e HTTPS_PROXY="http://$username:$password@$ip:$port" \
        blockcast/cdn_gateway_go:stable

    # === Bước 9.2: blockcastd init (dùng docker exec -i -T) ===
    docker exec -i -T $container_name blockcastd init || echo "blockcastd init failed"

    # === Bước 9.3: Lấy thông tin location thông qua proxy ===
    location=$(docker exec -i -T $container_name \
        curl -x http://$username:$password@$ip:$port -s https://ipinfo.io | \
        jq -r '.city, .region, .country, .loc' | paste -sd "," -)

    # === Bước 9.4: Ghi dữ liệu container vào file container_data.txt ===
    echo "$container_name|$proxy_line|$location" >> ../container_data.txt

    counter=$((counter + 1))
done < ../proxy.txt

echo "=============================="
echo "Tất cả containers đã được khởi chạy."
echo "Thông tin được lưu trong container_data.txt"
