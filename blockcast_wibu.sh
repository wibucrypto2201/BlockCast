#!/bin/bash

# blockcast_wibu.sh
# Author: Grimoire+ (OpenAI)
# Description: Clone toàn bộ repo, up container và lấy dữ liệu theo đúng số proxy.txt

REPO_URL="https://github.com/wibucrypto2201/beacon-docker-compose.git"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OUTPUT_FILE="${SCRIPT_DIR}/blockcast_data.txt"

set +e

# 1️⃣ Kiểm tra proxy.txt tồn tại
if [ ! -f "${SCRIPT_DIR}/proxy.txt" ]; then
    echo "❌ proxy.txt không tìm thấy!"
    exit 1
fi

# 2️⃣ Dọn file dữ liệu cũ
echo "" > "${OUTPUT_FILE}"

# 3️⃣ Phase 1: Clone repo và up container
instance_id=1
while IFS= read -r proxy_line || [[ -n "$proxy_line" ]]; do
    host_port=$((8000 + instance_id))
    project_name="blockcast_${instance_id}"
    repo_dir="${SCRIPT_DIR}/beacon-docker-compose-${instance_id}"

    echo "🔎 [Instance ${instance_id}] Đang setup container..."

    # Clone repo
    if [ -d "${repo_dir}" ]; then
        echo "⚠️  Repo ${repo_dir} đã tồn tại — đang xóa..."
        rm -rf "${repo_dir}"
    fi
    git clone "$REPO_URL" "${repo_dir}" > /dev/null 2>&1
    echo "✅ [Instance ${instance_id}] Repo cloned!"

    cd "${repo_dir}" || continue

    # Pull images
    echo "🔄 Pulling image..."
    docker compose pull > /dev/null 2>&1

    # Up container
    echo "🚀 Starting container..."
    INSTANCE_ID=$instance_id \
    PROXY_AUTH=$proxy_line \
    HOST_PORT=$host_port \
    docker compose -p "${project_name}" up -d > /dev/null 2>&1

    echo "✅ [Instance ${instance_id}] Container is up!"
    echo "-----------------------------"

    cd "${SCRIPT_DIR}" || continue
    ((instance_id++))
done < "${SCRIPT_DIR}/proxy.txt"

echo "⏳ Waiting for all containers to be fully ready..."
sleep 20  # ⏳ Cho container khởi chạy đầy đủ

# 4️⃣ Phase 2: Lấy register URL + location
instance_id=1
while IFS= read -r proxy_line || [[ -n "$proxy_line" ]]; do
    project_name="blockcast_${instance_id}"
    repo_dir="${SCRIPT_DIR}/beacon-docker-compose-${instance_id}"

    register_url="ERROR"
    location="ERROR"

    if [ -d "${repo_dir}" ]; then
        cd "${repo_dir}" || continue

        echo "🔗 [Instance ${instance_id}] Getting register URL..."
        register_url=$(docker compose -p "${project_name}" \
            exec -T blockcastd \
            bash -c "export HTTP_PROXY='http://${proxy_line}'; export HTTPS_PROXY='http://${proxy_line}'; blockcastd init" 2>/dev/null | grep -Eo 'http[s]?://[^[:space:]]*')
        [ -z "$register_url" ] && register_url="ERROR"

        echo "🌍 [Instance ${instance_id}] Getting location info..."
        location=$(docker compose -p "${project_name}" \
            exec -T blockcastd \
            bash -c "export HTTP_PROXY='http://${proxy_line}'; export HTTPS_PROXY='http://${proxy_line}'; curl -s https://ipinfo.io" | jq -r '[.city, .region, .country, .loc] | join(\", \")' 2>/dev/null)
        [ -z "$location" ] && location="ERROR"
    fi

    # ✅ Ghi ra file, luôn đủ 1 dòng cho mỗi proxy
    echo "${register_url}|${location}" >> "${OUTPUT_FILE}"

    echo "✅ [Instance ${instance_id}] Done:"
    echo "${register_url}|${location}"
    echo "-----------------------------"

    cd "${SCRIPT_DIR}" || continue
    ((instance_id++))
done < "${SCRIPT_DIR}/proxy.txt"

echo "🎉 Tất cả container đã được khởi chạy và lấy thông tin thành công!"
echo "📦 Dữ liệu đã được lưu tại: ${OUTPUT_FILE}"
