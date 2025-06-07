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
docker pull blockcast/cdn_gateway_go:stable

# === Bước 8: Hỏi số lượng container cần chạy ===
read -p "Nhập số lượng container cần chạy (Enter để chạy hết proxy.txt): " max_containers
max_containers=${max_containers:-9999}

# === Bước 9: Generate docker-compose.generated.yml ===
INPUT_FILE="../proxy.txt"
OUTPUT_FILE="docker-compose.generated.yml"

echo "version: '3.8'" > $OUTPUT_FILE
echo "" >> $OUTPUT_FILE
echo "services:" >> $OUTPUT_FILE

counter=1
while IFS= read -r proxy_line || [[ -n "$proxy_line" ]]; do
    if [ "$counter" -gt "$max_containers" ]; then
        echo "Đã generate đủ số lượng container yêu cầu: $max_containers"
        break
    fi

    username=$(echo "$proxy_line" | cut -d':' -f1)
    pass_ip_port=$(echo "$proxy_line" | cut -d':' -f2-)
    password=$(echo "$pass_ip_port" | cut -d'@' -f1)
    ip_port=$(echo "$pass_ip_port" | cut -d'@' -f2)
    ip=$(echo "$ip_port" | cut -d':' -f1)
    port=$(echo "$ip_port" | cut -d':' -f2)

    container_name="blockcastd_$counter"

    cat <<EOF >> $OUTPUT_FILE
  $container_name:
    image: blockcast/cdn_gateway_go:stable
    container_name: $container_name
    environment:
      - HTTP_PROXY=http://$username:$password@$ip:$port
      - HTTPS_PROXY=http://$username:$password@$ip:$port
    command: /usr/bin/blockcastd -logtostderr=true -v=0
    volumes:
      - \${HOME}/.blockcast/certs:/var/opt/magma/certs
      - \${HOME}/.blockcast/snowflake:/etc/snowflake
      - /var/run/docker.sock:/var/run/docker.sock
    restart: always

EOF

    counter=$((counter + 1))
done < "$INPUT_FILE"

# === Thêm service watchtower vào file YAML ===
cat <<EOF >> $OUTPUT_FILE
  watchtower:
    image: containrrr/watchtower
    environment:
      - WATCHTOWER_LABEL_ENABLE=true
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
EOF

echo "✅ Đã generate $OUTPUT_FILE thành công!"

# === Bước 10: Chạy containers ===
docker compose -f docker-compose.generated.yml up -d

echo "=============================="
echo "Tất cả containers đã được khởi chạy từ docker-compose.generated.yml!"
