#!/bin/bash

REPO_URL="https://github.com/wibucrypto2201/beacon-docker-compose.git"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OUTPUT_FILE="${SCRIPT_DIR}/blockcast_data.txt"

set +e

if [ ! -f "${SCRIPT_DIR}/proxy.txt" ]; then
    echo "❌ proxy.txt không tìm thấy!"
    exit 1
fi

echo "" > "${OUTPUT_FILE}"

instance_id=1
while IFS= read -r proxy_line || [[ -n "$proxy_line" ]]; do
    host_port=$((8000 + instance_id))
    project_name="blockcast_${instance_id}"
    repo_dir="${SCRIPT_DIR}/beacon-docker-compose-${instance_id}"

    echo "🔎 [Instance ${instance_id}] Bắt đầu setup container..."

    if [ -d "${repo_dir}" ]; then
        echo "⚠️  [Instance ${instance_id}] Repo tồn tại — xóa để clone lại..."
        rm -rf "${repo_dir}"
    fi
    git clone "$REPO_URL" "${repo_dir}" > /dev/null 2>&1
    echo "✅ [Instance ${instance_id}] Clone xong!"

    cd "${repo_dir}" || continue

    echo "🔄 Pulling image..."
    docker compose pull > /dev/null 2>&1

    echo "🚀 Starting container..."
    INSTANCE_ID=$instance_id \
    PROXY_AUTH=$proxy_line \
    HOST_PORT=$host_port \
    docker compose -p "${project_name}" up -d > /dev/null 2>&1

    echo "✅ [Instance ${instance_id}] Container đã chạy!"
    echo "-----------------------------"

    cd "${SCRIPT_DIR}" || continue
    ((instance_id++))
done < "${SCRIPT_DIR}/proxy.txt"

echo "⏳ Đang chờ container khởi chạy..."
sleep 15

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
            exec -T -e HTTP_PROXY="http://${proxy_line}" \
                    -e HTTPS_PROXY="http://${proxy_line}" \
                    blockcastd blockcastd init 2>/dev/null | grep -Eo 'http[s]?://[^[:space:]]*')
        if [ -z "$register_url" ]; then
            register_url="ERROR"
        fi

        echo "🌍 [Instance ${instance_id}] Getting location info..."
        location=$(docker compose -p "${project_name}" \
            exec -T blockcastd bash -c \
            "export HTTP_PROXY='http://${proxy_line}'; export HTTPS_PROXY='http://${proxy_line}'; curl -s https://ipinfo.io" | jq -r '[.city, .region, .country, .loc] | join(\", \")' 2>/dev/null)
        if [ -z "$location" ]; then
            location="ERROR"
        fi
    fi

    echo "${register_url}|${location}" >> "${OUTPUT_FILE}"

    echo "✅ [Instance ${instance_id}] Done:"
    echo "${register_url}|${location}"
    echo "-----------------------------"

    cd "${SCRIPT_DIR}" || continue
    ((instance_id++))
done < "${SCRIPT_DIR}/proxy.txt"

echo "🎉 Tất cả container đã được khởi chạy và lấy thông tin thành công!"
echo "📦 Dữ liệu đã được lưu tại: ${OUTPUT_FILE}"
