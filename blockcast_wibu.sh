#!/bin/bash

REPO="beacon-docker-compose"
REPO_URL="https://github.com/wibucrypto2201/beacon-docker-compose.git"

# 1️⃣ Kiểm tra proxy.txt ở thư mục cha
if [ ! -f "../proxy.txt" ]; then
    echo "❌ Error: proxy.txt không tìm thấy! Vui lòng đặt file proxy.txt ở thư mục cha của $REPO"
    exit 1
fi

# 2️⃣ Xóa repo cũ nếu đã tồn tại
if [ -d "$REPO" ]; then
    echo "⚠️  Repo $REPO đã tồn tại — đang xóa để clone lại..."
    rm -rf "$REPO"
fi

# 3️⃣ Clone repo mới
git clone "$REPO_URL"

cd "$REPO" || exit 1

# 4️⃣ Pull latest images
docker compose pull

# 5️⃣ Start containers theo proxy.txt
instance_id=1
while IFS= read -r proxy_line || [[ -n "$proxy_line" ]]; do
    proxy_port=$((8080 + instance_id))
    echo "🟢 Starting container_${instance_id} with proxy: ${proxy_line} on port ${proxy_port}"

    INSTANCE_ID=$instance_id \
    PROXY_AUTH=$proxy_line \
    PROXY_PORT=$proxy_port \
    docker compose up -d

    ((instance_id++))
done < ../proxy.txt

echo "✅ Tất cả container đã được khởi chạy thành công!"
