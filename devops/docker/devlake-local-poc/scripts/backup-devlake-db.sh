#!/usr/bin/env bash
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/backup-devlake-db.sh [backup-dir]

Creates a gzip-compressed mysqldump of the DevLake MySQL database.

Default backup-dir:
  ./backups

Example:
  scripts/backup-devlake-db.sh
  scripts/backup-devlake-db.sh ./backups
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
compose_dir="$(cd "${script_dir}/.." && pwd)"
backup_dir="${1:-${compose_dir}/backups}"
timestamp="$(date +%Y%m%d-%H%M%S)"
backup_file="${backup_dir}/lake-backup-${timestamp}.sql.gz"
tmp_file="${backup_file}.tmp"
devlake_was_running=false

cleanup() {
  rm -f "${tmp_file}"
  if [[ "${devlake_was_running}" == "true" ]]; then
    docker compose up -d devlake >/dev/null
  fi
}
trap cleanup ERR INT TERM

mkdir -p "${backup_dir}"
cd "${compose_dir}"

if docker compose ps --status running --services | grep -qx 'devlake'; then
  devlake_was_running=true
  docker compose stop devlake >/dev/null
fi

docker compose exec -T mysql sh -c \
  'MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysqldump --single-transaction --quick --routines --triggers --events -uroot lake' \
  | gzip -9 > "${tmp_file}"

gzip -t "${tmp_file}"
mv "${tmp_file}" "${backup_file}"

if [[ "${devlake_was_running}" == "true" ]]; then
  docker compose up -d devlake >/dev/null
  devlake_was_running=false
fi

ls -lh "${backup_file}"
