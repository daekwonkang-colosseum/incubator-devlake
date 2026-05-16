# DevLake + Grafana 로컬 올인원 스택

콜로 엔지니어링팀의 **DORA 메트릭 PoC**를 위한 로컬 환경입니다.
Jira·GitHub 데이터를 자동 수집해 Grafana에서 시각화합니다.

---

## ⚠️ 시작 전 — Confluence 지원에 대한 안내

DevLake는 **Confluence 네이티브 플러그인을 제공하지 않습니다** (2026-05 기준 공식 지원: GitHub, GitLab, Jira, Jenkins, BitBucket, Azure DevOps, Sonarqube 등).

**권장 옵션**
- ✅ **이번 PoC에서는 Confluence 제외, Jira + GitHub만으로 진행**
  Confluence 데이터는 DORA 4대 메트릭(배포 빈도·리드 타임·CFR·MTTR)과 직접 관련이 없습니다.
- Confluence 문서 활동을 보조 지표로 보고 싶다면, **Webhook 플러그인**을 통해 Atlassian Automation 또는 Forge 앱에서 데이터를 푸시하는 방식을 별도 트랙으로 검토하세요.

---

## 사전 준비

- Docker Desktop 또는 Docker Engine + Compose v2.2.3 이상
- 메모리 4GB 이상 할당
- 포트 가용성: `3002`, `4000`, `8080`, `3306` (로컬 바인딩)

---

## 빠른 시작

현재 스택은 Apache DevLake `main` 브랜치 기반 로컬 백엔드 이미지(`devlake-local:main`)와 MySQL 8을 사용합니다.
Config UI와 Grafana 대시보드는 기존 `v1.0.3-beta12` 이미지를 유지합니다.

### 1. 환경 변수 파일 준비

```bash
cd devops/docker/devlake-local-poc
cp env.example .env
```

### 2. ENCRYPTION_SECRET 생성

DevLake가 Jira·GitHub 토큰을 암호화할 때 사용합니다. **한 번 설정 후 절대 변경 금지** (변경 시 저장된 자격증명 복호화 불가).

```bash
openssl rand -base64 2000 | tr -dc 'A-Z' | fold -w 128 | head -n 1
```

출력된 128자 문자열을 `.env`의 `ENCRYPTION_SECRET=` 뒤에 붙여 넣습니다.

### 3. 로컬 DevLake main 이미지 빌드

GitHub GraphQL `Collect Issues` 실패 수정이 포함된 DevLake main 백엔드 이미지를 로컬에서 빌드합니다.

```bash
cd /path/to/incubator-devlake-fork

SHA=$(git rev-parse --short=8 HEAD)
docker buildx build --load --platform linux/arm64 \
  -t devlake-local:main \
  -t devlake-local:main-${SHA} \
  --build-arg TAG=main \
  --build-arg SHA=${SHA} \
  -f devops/docker/devlake-local-poc/Dockerfile.devlake-main-local \
  backend
```

Intel/AMD 머신에서는 `--platform linux/amd64`로 변경하세요.

현재 로컬 빌드 기준 커밋은 `420e494b`입니다.
로컬 이미지는 GitHub 수집과 DORA/Issue Trace 프로젝트 메트릭에 필요한 Go 플러그인만 포함해 빌드합니다:
`github`, `github_graphql`, `gitextractor`, `org`, `dora`, `issue_trace`, `refdiff`, `jira`, `webhook`, `jenkins`.

### 4. 컨테이너 기동

```bash
cd devops/docker/devlake-local-poc
docker compose up -d
```

초기 부팅에 30~60초 정도 소요됩니다. (`docker compose logs -f devlake`로 진행 확인 가능)

### 5. UI 접속

| UI                          | URL                                            | 계정              |
| --------------------------- | ---------------------------------------------- | ----------------- |
| Config UI (데이터 소스 설정)   | http://localhost:4000                          | (미설정 시 free) |
| Grafana 대시보드             | http://localhost:3002                          | `admin` / `admin` |
| DevLake API (Swagger)        | http://localhost:8080/swagger/index.html       | -                 |

---

## 데이터 소스 연결 (Config UI 안에서 진행)

### Jira (콜로솔루션 Atlassian Cloud)

1. `Connections` → `Add Connection` → **Jira**
2. 입력 값:
   - **Endpoint URL**: `https://colosseum.atlassian.net/rest/`
   - **Username**: Atlassian 로그인 이메일
   - **Password**: [Atlassian API Token](https://id.atlassian.com/manage-profile/security/api-tokens) (실제 비밀번호 아님)
3. `Add Scope` → 수집할 Jira 프로젝트 선택
4. **Scope Config**에서 Issue Type ↔ DevLake Domain 매핑
   - 예: `Bug` → `BUG`, `Incident` → `INCIDENT`, `Story/Task` → `REQUIREMENT`

### GitHub

1. `Connections` → `Add Connection` → **GitHub**
2. 입력 값:
   - **Endpoint URL**: `https://api.github.com/`
   - **Auth Method**: Personal Access Token (또는 GitHub App)
   - **Token**: [PAT 발급](https://github.com/settings/tokens) — scope `repo`, `read:org`, `read:user` 필요
3. `Add Scope` → 수집할 Repo 선택
4. **Scope Config**에서 CI/CD 매핑
   - `Deployment` 판정 규칙: 워크플로우명 정규식 (예: `^deploy-prod$`)
   - `Production` 환경 식별자 매핑

### Project 구성 (DORA 활성화)

1. `Projects` → `New Project`
2. 이름은 그라운드 룰의 프로젝트 단위로 분리 — `colo-1-0`, `cgs`, `cgkr`
3. **Settings → Enable DORA** 토글 ON
4. 위에서 만든 Jira·GitHub Connection을 이 프로젝트에 연결
5. `Blueprints` → `Create Blueprint` → 초기엔 **Manual 트리거**로 시작하고 안정화되면 cron 활성화

---

## Grafana 대시보드 접근

Grafana(`http://localhost:3002`) 좌측 메뉴 `Dashboards` → `DORA` 폴더에 빌트인 대시보드가 미리 들어가 있습니다.

- **DORA** — 4대 메트릭 종합 뷰
- **Engineering Throughput** — PR/이슈 처리량
- **Engineering Overview** — 종합

> Tip: 빌트인 대시보드는 그대로 두고, `Save As`로 복제해서 우리 그라운드 룰의 임계치(주 2회/2~3일/15%/300분)를 Threshold 라인으로 얹는 방식을 권장합니다.

---

## 정지 / 데이터 관리

```bash
# 정지 (볼륨 유지)
docker compose down

# DevLake DB 백업
scripts/backup-devlake-db.sh

# 데이터까지 모두 삭제
docker compose down -v

# 컨테이너 로그 확인
docker compose logs -f devlake
```

백업 파일은 기본적으로 `backups/lake-backup-YYYYMMDD-HHMMSS.sql.gz` 형식으로 생성됩니다.
DevLake backend가 `_devlake_locking_stub` 메타데이터 락을 잡고 있을 수 있어, 백업 스크립트는 `devlake` 컨테이너만 잠깐 내린 뒤 MySQL 덤프를 뜨고 다시 올립니다.

---

## 트러블슈팅

| 증상                                | 원인 / 조치                                                                |
| ----------------------------------- | -------------------------------------------------------------------------- |
| Config UI에서 "API unreachable"     | devlake 컨테이너 부팅 중. 30초 대기 후 새로고침                            |
| 컨테이너가 즉시 종료됨              | `.env`의 `ENCRYPTION_SECRET`이 비어 있음. openssl 명령으로 생성 후 재기동  |
| Jira 401 Unauthorized               | 비밀번호 입력했을 가능성. Atlassian API Token으로 교체                     |
| GitHub 403 (rate limit)             | PAT scope 부족 또는 호출량 초과. GitHub App 방식으로 전환 검토              |
| MySQL 포트 충돌                     | 호스트에서 3306 사용 중. docker-compose.yml에서 `127.0.0.1:13306:3306` 등으로 변경 |
| 대시보드 변경사항이 재기동 후 사라짐 | `grafana-storage` 볼륨이 정상 유지되는지 확인 (down -v 했는지 점검)         |

---

## 다음 단계 (운영 환경 적용 시)

이 스택은 **로컬 PoC 용도**입니다. 실제 운영 단계로 넘어갈 때:

- MySQL을 외부 매니지드 DB(RDS 등)로 분리
- Grafana는 SSO 연동된 별도 인스턴스로 운영 (DevLake DB만 데이터 소스로 추가)
- `ENCRYPTION_SECRET`은 시크릿 매니저(AWS Secrets Manager, Vault 등)에 보관
- 컨테이너 리소스 limit / autoscaling 검토
- Helm 차트로 K8s 배포 전환

---

## 참고 링크

- Apache DevLake 공식 문서: https://devlake.apache.org/docs/
- Docker Compose 설치 가이드: https://devlake.apache.org/docs/GettingStarted/DockerComposeSetup/
- 지원 데이터 소스: https://devlake.apache.org/docs/Overview/SupportedDataSources/
- DORA 대시보드 가이드: https://devlake.apache.org/docs/DORA
