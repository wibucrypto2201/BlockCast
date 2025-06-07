#!/bin/bash

REPO="beacon-docker-compose"
REPO_URL="https://github.com/wibucrypto2201/beacon-docker-compose.git"

# Lấy thư mục chứa script để đảm bảo đường dẫn proxy.txt và repo chính xác
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 1️⃣ Kiểm tra proxy.txt tồn tại
if [ ! -f "${SCRIPT_DIR}/proxy.txt" ]; then
    echo "❌ Error: proxy.txt không tìm thấy! Vui lòng đặt file proxy.txt cùng thư mục với blockcast_wibu.sh"
    exit 1
fi

# 2️⃣ Xóa repo cũ nếu đã tồn tại
if [ -d "${SCRIPT_DIR}/${REPO}" ]; then
    echo "⚠️  Repo ${REPO} đã tồn tại — đang xóa để clone lại..."
    rm -rf "${SCRIPT_DIR:?}/${REPO}"
fi

# 3️⃣ Clone repo mới
git clone "$REPO_URL" "${SCRIPT_DIR}/${REPO}"

cd "${SCRIPT_DIR}/${REPO}" || exit 1

# 4️⃣ Pull latest images
docker compose pull

# 5️⃣ Start containers theo proxy.txt
instance_id=1
while IFS= read -r proxy_line || [[ -n "$proxy_line" ]]; do
    host_port=$((8080 + instance_id))
    project_name="blockcast_${instance_id}"
    echo "🟢 Starting container_${instance_id} with proxy: ${proxy_line} on port ${host_port} (Project: ${project_name})"

    INSTANCE_ID=$instance_id \
    PROXY_AUTH=$proxy_line \
    HOST_PORT=$host_port \
    docker compose -p "${project_name}" up -d

    ((instance_id++))
done < "${SCRIPT_DIR}/proxy.txt"

echo "✅ Tất cả container đã được khởi chạy thành công!"
