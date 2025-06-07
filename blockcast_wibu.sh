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

# Phase 1: Clone + Pull + Up
instance_id=1
while IFS= read -r proxy_line || [[ -n "$proxy_line" ]]; do
    host_port=$((8000 + instance_id))
    project_name="blockcast_${instance_id}"
    repo_dir="${SCRIPT_DIR}/beacon-docker-compose-${instance_id}"

    echo "🔎 [Instance ${instance_id}] Setup container..."

    if [ -d "${repo_dir}" ]; then
        rm -rf "${repo_dir}"
    fi
    git clone "$REPO_URL" "${repo_dir}" > /dev/null 2>&1

    cd "${repo_dir}" || continue

    docker compose pull > /dev/null 2>&1

    INSTANCE_ID=$instance_id \
    PROXY_AUTH=$proxy_line \
    HOST_PORT=$host_port \
    docker compose -p "${project_name}" up -d > /dev/null 2>&1

    echo "✅ [Instance ${instance_id}] Container started!"
    echo "-----------------------------"

    cd "${SCRIPT_DIR}" || continue
    ((instance_id++))
done < "${SCRIPT_DIR}/proxy.txt"

echo "⏳ Waiting for containers to fully initialize..."
sleep 20

# Phase 2: Exec commands inside container
instance_id=1
while IFS= read -r proxy_line || [[ -n "$proxy_line" ]]; do
    project_name="blockcast_${instance_id}"
    repo_dir="${SCRIPT_DIR}/beacon-docker-compose-${instance_id}"

    register_url="ERROR"
    location="ERROR"

    if [ -d "${repo_dir}" ]; then
        cd "${repo_dir}" || continue

        echo "🔗 [Instance ${instance_id}] Getting register URL..."

        # Retry loop for blockcastd init (max 5 tries)
        for attempt in {1..5}; do
            register_url=$(docker compose -p "${project_name}" \
                exec -T blockcastd \
                bash -c "export HTTP_PROXY='http://${proxy_line}'; blockcastd init" 2>/dev/null | grep -Eo 'http[s]?://[^[:space:]]*')
            if [ -n "$register_url" ]; then
                break
            fi
            echo "⏳ [Instance ${instance_id}] Waiting for blockcastd... (Attempt $attempt/5)"
            sleep 5
        done
        [ -z "$register_url" ] && register_url="ERROR"

        echo "🌍 [Instance ${instance_id}] Getting location info..."
        for attempt in {1..5}; do
            location=$(docker compose -p "${project_name}" \
                exec -T blockcastd \
                bash -c "export HTTP_PROXY='http://${proxy_line}'; curl -s https://ipinfo.io" | jq -r '[.city, .region, .country, .loc] | join(\", \")' 2>/dev/null)
            if [ -n "$location" ]; then
                break
            fi
            echo "⏳ [Instance ${instance_id}] Waiting for curl... (Attempt $attempt/5)"
            sleep 5
        done
        [ -z "$location" ] && location="ERROR"
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
