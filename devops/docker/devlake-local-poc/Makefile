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

PROJECT ?= devlake-local-docker-compose
COMPOSE := docker compose -p $(PROJECT)
REPO_ROOT := $(abspath ../../..)
SHA := $(shell git -C $(REPO_ROOT) rev-parse --short=8 HEAD)
PLATFORM ?= linux/arm64
BACKUP_FILEPATH ?=
DEVLAKE_PLUGINS ?= github,github_graphql,gitextractor,org,dora,issue_trace,refdiff,jira,webhook,jenkins,argocd

.PHONY: help up down restart ps logs logs-devlake logs-mysql db-backup db-restore config build

help:
	@printf '%s\n' 'DevLake local PoC commands'
	@printf '%s\n' ''
	@printf '%s\n' 'Project name is fixed to reuse the existing DB volumes:'
	@printf '  PROJECT=%s\n' '$(PROJECT)'
	@printf '%s\n' ''
	@printf '%s\n' 'Targets:'
	@printf '%s\n' '  make up           Start DevLake, MySQL, Config UI, and Grafana'
	@printf '%s\n' '  make down         Stop containers without deleting volumes'
	@printf '%s\n' '  make restart      Stop and start containers without deleting volumes'
	@printf '%s\n' '  make ps           Show service status'
	@printf '%s\n' '  make logs         Follow all service logs'
	@printf '%s\n' '  make logs-devlake Follow DevLake backend logs'
	@printf '%s\n' '  make logs-mysql   Follow MySQL logs'
	@printf '%s\n' '  make db-backup    Create a gzip DB backup under ./backups'
	@printf '%s\n' '  make db-restore  Restore DB from a backup file'
	@printf '%s\n' '  make config       Validate the compose configuration'
	@printf '%s\n' '  make build        Build devlake-local:main from this fork'
	@printf '%s\n' ''
	@printf '%s\n' 'Volume-deleting commands are intentionally not provided here.'

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

restart: down up

ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f

logs-devlake:
	$(COMPOSE) logs -f devlake

logs-mysql:
	$(COMPOSE) logs -f mysql

db-backup:
	COMPOSE_PROJECT_NAME=$(PROJECT) ./scripts/backup-devlake-db.sh

db-restore:
	@test -n "$(BACKUP_FILEPATH)" || (printf '%s\n' 'Usage: make db-restore BACKUP_FILEPATH=/path/to/lake-backup.sql.gz' >&2; exit 2)
	COMPOSE_PROJECT_NAME=$(PROJECT) ./scripts/restore-devlake-db.sh "$(BACKUP_FILEPATH)"

config:
	$(COMPOSE) config --quiet

build:
	docker buildx build --load --platform $(PLATFORM) \
		-t devlake-local:main \
		-t devlake-local:main-$(SHA) \
		--build-arg TAG=main \
		--build-arg SHA=$(SHA) \
		--build-arg DEVLAKE_PLUGINS=$(DEVLAKE_PLUGINS) \
		-f Dockerfile.devlake-main-local \
		$(REPO_ROOT)/backend
