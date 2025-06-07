#!/bin/bash

REPO_URL="https://github.com/wibucrypto2201/beacon-docker-compose.git"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 1️⃣ Check proxy.txt tồn tại
if [ ! -f "${SCRIPT_DIR}/proxy.txt" ]; then
    echo "❌ Error: proxy.txt không tìm thấy! Vui lòng đặt file proxy.txt cùng thư mục với blockcast_wibu.sh"
    exit 1
fi

instance_id=1
while IFS= read -r proxy_line || [[ -n "$proxy_line" ]]; do
    proxy_port=$(echo "$proxy_line" | awk -F':' '{print $NF}')
    project_name="blockcast_${instance_id}"
    repo_dir="${SCRIPT_DIR}/beacon-docker-compose-${instance_id}"

    if [ -d "${repo_dir}" ]; then
        echo "⚠️  Repo ${repo_dir} đã tồn tại — đang xóa để clone lại..."
        rm -rf "${repo_dir}"
    fi

    git clone "$REPO_URL" "${repo_dir}"
    cd "${repo_dir}" || exit 1

    echo "🟢 Starting container_${instance_id} with proxy: ${proxy_line} on port ${proxy_port} (Project: ${project_name})"

    docker compose pull

    INSTANCE_ID=$instance_id \
    PROXY_AUTH=$proxy_line \
    HOST_PORT=$proxy_port \
    docker compose -p "${project_name}" up -d

    ((instance_id++))
done < "${SCRIPT_DIR}/proxy.txt"

echo "✅ Tất cả container đã được khởi chạy thành công!"
