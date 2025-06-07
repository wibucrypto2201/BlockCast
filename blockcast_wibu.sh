#!/bin/bash

# blockcast_wibu.sh
# Author: Grimoire+ (OpenAI)
# Description: Tự động clone repo, pull image, up container,
#              lấy register URL và location từ từng container blockcastd,
#              và ghi ra blockcast_data.txt với format: register_url|location

REPO_URL="https://github.com/wibucrypto2201/beacon-docker-compose.git"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OUTPUT_FILE="${SCRIPT_DIR}/blockcast_data.txt"

# 1️⃣ Kiểm tra proxy.txt tồn tại
if [ ! -f "${SCRIPT_DIR}/proxy.txt" ]; then
    echo "❌ Error: proxy.txt không tìm thấy! Vui lòng đặt file proxy.txt cùng thư mục với blockcast_wibu.sh"
    exit 1
fi

echo "" > "${OUTPUT_FILE}"   # Clear output file

instance_id=1
while IFS= read -r proxy_line || [[ -n "$proxy_line" ]]; do
    host_port=$((8000 + instance_id))   # Sử dụng port 8001, 8002, ...
    project_name="blockcast_${instance_id}"
    repo_dir="${SCRIPT_DIR}/beacon-docker-compose-${instance_id}"

    echo "🔎 [Instance ${instance_id}] Checking container..."

    # Clone repo nếu chưa tồn tại (hoặc refresh)
    if [ -d "${repo_dir}" ]; then
        echo "⚠️  Repo ${repo_dir} đã tồn tại — đang xóa để clone lại..."
        rm -rf "${repo_dir}"
    fi
    git clone "$REPO_URL" "${repo_dir}"
    cd "${repo_dir}" || exit 1

    echo "🔄 [Instance ${instance_id}] Pulling latest images..."
    docker compose pull

    echo "🚀 [Instance ${instance_id}] Starting container..."
    INSTANCE_ID=$instance_id \
    PROXY_AUTH=$proxy_line \
    HOST_PORT=$host_port \
    docker compose -p "${project_name}" up -d

    echo "🔗 [Instance ${instance_id}] Getting register URL..."
    register_url=$(docker compose -p "${project_name}" exec blockcastd blockcastd init 2>/dev/null | grep -Eo 'http[s]?://[^[:space:]]*')
    if [ -z "$register_url" ]; then
        register_url="ERROR"
    fi

    echo "🌍 [Instance ${instance_id}] Getting location info..."
    location=$(docker compose -p "${project_name}" exec blockcastd curl -s https://ipinfo.io | jq -r '[.city, .region, .country, .loc] | join(", ")' 2>/dev/null)
    if [ -z "$location" ]; then
        location="ERROR"
    fi

    echo "${register_url}|${location}" >> "${OUTPUT_FILE}"

    echo "✅ [Instance ${instance_id}] Done:"
    echo "${register_url}|${location}"
    echo "-----------------------------"

    ((instance_id++))
done < "${SCRIPT_DIR}/proxy.txt"

echo "🎉 Tất cả container đã được khởi chạy thành công!"
echo "📦 Dữ liệu đã được lưu tại: ${OUTPUT_FILE}"
