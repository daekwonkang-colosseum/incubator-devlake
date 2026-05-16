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
  scripts/restore-devlake-db.sh /path/to/lake-backup.sql.gz

Restores the gzip-compressed DevLake MySQL dump into the lake database.

Safety behavior:
  - Validates the gzip backup before touching MySQL.
  - Stops the devlake backend before replacing the lake database.
  - Restarts the backend only after a successful restore.
  - Leaves the backend stopped if restore fails after it was stopped.

Example:
  scripts/restore-devlake-db.sh ./backups/lake-backup-20260516-235357.sql.gz
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

backup_arg="$1"
if [[ "${backup_arg}" = /* ]]; then
  backup_file="${backup_arg}"
else
  backup_file="$(pwd)/${backup_arg}"
fi

if [[ ! -f "${backup_file}" ]]; then
  echo "Backup file not found: ${backup_file}" >&2
  exit 2
fi

gzip -t "${backup_file}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
compose_dir="$(cd "${script_dir}/.." && pwd)"
cd "${compose_dir}"

if ! docker compose ps --status running --services | grep -qx 'mysql'; then
  echo "MySQL service is not running. Start the stack first with: make up" >&2
  exit 2
fi

devlake_was_running=false
if docker compose ps --status running --services | grep -qx 'devlake'; then
  devlake_was_running=true
  docker compose stop devlake >/dev/null
fi

on_error() {
  echo "Restore failed. The devlake backend was left stopped to avoid using a partial restore." >&2
}
trap on_error ERR

docker compose exec -T mysql sh -c \
  'MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysql -uroot -e "DROP DATABASE IF EXISTS lake; CREATE DATABASE lake CHARACTER SET utf8mb4 COLLATE utf8mb4_bin; GRANT ALL PRIVILEGES ON lake.* TO '\''merico'\''@'\''%'\''; FLUSH PRIVILEGES;"'

gunzip -c "${backup_file}" | docker compose exec -T mysql sh -c \
  'MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysql -uroot lake'

trap - ERR

if [[ "${devlake_was_running}" == "true" ]]; then
  docker compose up -d devlake >/dev/null
fi

docker compose exec -T mysql sh -c \
  'MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysql -uroot -N -e "SELECT COUNT(*) AS table_count FROM information_schema.tables WHERE table_schema='\''lake'\'';"'
