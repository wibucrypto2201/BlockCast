#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OUTPUT_FILE="${SCRIPT_DIR}/blockcast_data.txt"
echo "" > "${OUTPUT_FILE}"   # clear output file

instance_id=1
while IFS= read -r proxy_line || [[ -n "$proxy_line" ]]; do
    dir="${SCRIPT_DIR}/beacon-docker-compose-${instance_id}"
    project_name="blockcast_${instance_id}"

    if [ -d "${dir}" ]; then
        echo "🔗 [Instance ${instance_id}] Getting register URL..."
        register_url=$(docker compose -p "${project_name}" -f "${dir}/docker-compose.yml" exec blockcastd blockcastd init 2>/dev/null | grep -Eo 'http[s]?://[^[:space:]]*')
        if [ -z "$register_url" ]; then
            register_url="ERROR"
        fi

        echo "🌍 [Instance ${instance_id}] Getting location info..."
        location=$(docker compose -p "${project_name}" -f "${dir}/docker-compose.yml" exec blockcastd curl -s https://ipinfo.io | jq -r '[.city, .region, .country, .loc] | join(", ")' 2>/dev/null)
        if [ -z "$location" ]; then
            location="ERROR"
        fi

        echo "${register_url}|${location}" >> "${OUTPUT_FILE}"

        echo "✅ Done for instance ${instance_id}:"
        echo "${register_url}|${location}"
    else
        echo "⚠️  Instance ${instance_id} chưa được setup container. Ghi lỗi."
        echo "ERROR|ERROR" >> "${OUTPUT_FILE}"
    fi

    echo "-----------------------------"
    ((instance_id++))
done < "${SCRIPT_DIR}/proxy.txt"

echo "🎉 Dữ liệu đã được lưu tại: ${OUTPUT_FILE}"
