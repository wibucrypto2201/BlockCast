#!/bin/bash

# blockcast_wibu.sh
# Author: Grimoire+ (OpenAI)
# Description: Clone toàn bộ repo, up toàn bộ container, sau đó mới bắt đầu exec lấy data để đảm bảo tuần tự theo proxy.txt.

REPO_URL="https://github.com/wibucrypto2201/beacon-docker-compose.git"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OUTPUT_FILE="${SCRIPT_DIR}/blockcast_data.txt"

# 1️⃣ Kiểm tra proxy.txt tồn tại
if [ ! -f "${SCRIPT_DIR}/proxy.txt" ]; then
    echo "❌ Error: proxy.txt không tìm thấy! Vui lòng đặt file proxy.txt cùng thư mục với blockcast_wibu.sh"
    exit 1
fi

echo "" > "${OUTPUT_FILE}"   # Clear output file

# 2️⃣ Phase 1: Clone repo + up container
instance_id=1
while IFS= read -r proxy_line || [[ -n "$proxy_line" ]]; do
    host_port=$((8000 + instance_id))
    project_name="blockcast_${instance_id}"
    repo_dir="${SCRIPT_DIR}/beacon-docker-compose-${instance_id}"

    echo "🔎 [Instance ${instance_id}] Bắt đầu setup container..."

    # Clone repo
    if [ -d "${repo_dir}" ]; then
        echo "⚠️  [Instance ${instance_id}] Repo đã tồn tại — đang xóa để clone lại..."
        rm -rf "${repo_dir}"
    fi
    git clone "$REPO_URL" "${repo_dir}" > /dev/null 2>&1
    echo "✅ [Instance ${instance_id}] Clone xong!"

    cd "${repo_dir}" || exit 1

    # Pull image
    echo "🔄 [Instance ${instance_id}] Pulling latest images..."
    docker compose pull > /dev/null 2>&1

    # Up container
    echo "🚀 [Instance ${instance_id}] Starting container..."
    INSTANCE_ID=$instance_id \
    PROXY_AUTH=$proxy_line \
    HOST_PORT=$host_port \
    docker compose -p "${project_name}" up -d > /dev/null 2>&1

    echo "✅ [Instance ${instance_id}] Container đã khởi chạy!"
    echo "-----------------------------"

    cd "${SCRIPT_DIR}" || exit 1
    ((instance_id++))
done < "${SCRIPT_DIR}/proxy.txt"

echo "⏳ Đang chờ tất cả container khởi chạy hoàn tất..."
sleep 10  # Cho container ổn định

# 3️⃣ Phase 2: Lấy register URL + location theo đúng proxy.txt
instance_id=1
while IFS= read -r proxy_line || [[ -n "$proxy_line" ]]; do
    project_name="blockcast_${instance_id}"
    repo_dir="${SCRIPT_DIR}/beacon-docker-compose-${instance_id}"

    if [ -d "${repo_dir}" ]; then
        cd "${repo_dir}" || exit 1

        echo "🔗 [Instance ${instance_id}] Getting register URL..."
        register_url=$(docker compose -p "${project_name}" \
            exec -e HTTP_PROXY="http://${proxy_line}" \
                 -e HTTPS_PROXY="http://${proxy_line}" \
                 blockcastd blockcastd init 2>/dev/null | grep -Eo 'http[s]?://[^[:space:]]*')
        if [ -z "$register_url" ]; then
            register_url="ERROR"
        fi

        echo "🌍 [Instance ${instance_id}] Getting location info..."
        location=$(docker compose -p "${project_name}" \
            exec -e HTTP_PROXY="http://${proxy_line}" \
                 -e HTTPS_PROXY="http://${proxy_line}" \
                 blockcastd curl -s https://ipinfo.io | jq -r '[.city, .region, .country, .loc] | join(", ")' 2>/dev/null)
        if [ -z "$location" ]; then
            location="ERROR"
        fi

        echo "${register_url}|${location}" >> "${OUTPUT_FILE}"

        echo "✅ [Instance ${instance_id}] Done:"
        echo "${register_url}|${location}"
    else
        echo "⚠️  [Instance ${instance_id}] Container chưa setup hoặc chưa chạy. Ghi lỗi."
        echo "ERROR|ERROR" >> "${OUTPUT_FILE}"
    fi

    echo "-----------------------------"
    cd "${SCRIPT_DIR}" || exit 1
    ((instance_id++))
done < "${SCRIPT_DIR}/proxy.txt"

echo "🎉 Tất cả container đã được khởi chạy và lấy thông tin thành công!"
echo "📦 Dữ liệu đã được lưu tại: ${OUTPUT_FILE}"
