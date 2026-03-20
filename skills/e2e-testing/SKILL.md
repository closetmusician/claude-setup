---
name: e2e-testing
description: Use when running full-stack e2e tests for Boardroom AI, verifying browser-level behavior against real backend/DB, executing YAML test cases with Claude-in-Chrome, generating tests from requirements, or debugging e2e test failures
---

# Boardroom AI — E2E Testing

## Routing — Pick the Right Path

| What you want to do | Go to |
|---------------------|-------|
| **Run a full e2e suite** ("run tests for FEAT-001 to FEAT-004") | `lead-orchestrator` skill → E2E Suite Mode |
| **Execute specific YAML tests** (step-by-step MCP translation) | `e2e-qa-runner` skill |
| **Generate YAML tests** from PRD requirements | `e2e-test-writer` skill |
| **Debug a failing e2e test** | Troubleshooting section below |
| **Ad-hoc UI inspection** | Claude-in-Chrome MCP directly |

**Rule of thumb:**
- Suite-level orchestration (multi-feature, walk-away-and-report) → `lead-orchestrator`
- Per-test execution (interpreting YAML steps, driving Chrome) → `e2e-qa-runner`
- Generating new tests from specs → `e2e-test-writer`
- This skill is for: prerequisites, troubleshooting, and common mistakes

## Prerequisites Checklist

Before running ANY e2e test, verify in order:

1. **Docker stack running:** `docker compose -f boardroom-ai/docker-compose.yml ps` — all 3 services healthy
2. **Backend healthy:** `curl -sf http://localhost:3456/health` returns 200
3. **Frontend running:** `curl -s -o /dev/null -w '%{http_code}' http://localhost:3000` returns 200
4. **Config source of truth:** `boardroom-ai/e2e/config.py` (all URLs, ports, credentials)
5. **Setup run:** `python boardroom-ai/e2e/setup.py` (creates user, login, project → `.state/session.json`)

If any fail, fix before proceeding. Do NOT skip steps.

Note: `run_all.py` calls `setup.py` automatically — you do NOT need to run setup separately if using `run_all.py`.

## Quick Commands

```bash
# Discover tests (no execution)
python boardroom-ai/e2e/run_all.py --dry-run

# Filter by feature
python boardroom-ai/e2e/run_all.py --feature FEAT-001 --dry-run

# Filter by priority + type
python boardroom-ai/e2e/run_all.py --priority P0 --type backend --dry-run
```

## The 8 Common Mistakes (and fixes)

Discovered during the first e2e test sessions:

### 1. Missing DB migration
**Symptom:** Table doesn't exist, 500 errors on agent endpoints
**Fix:** Check `docker-compose.yml` has mount for every file in `backend/migrations/`. Fresh DB: `docker compose down -v && up -d`

### 2. Wrong frontend routes
**Symptom:** 404 or blank page in browser
**Fix:** FE uses `/project/{id}` (SINGULAR). NOT `/projects/{id}`. Check `boardroom-ai/e2e/config.py` FE_ROUTES.

### 3. Wrong API prefixes
**Symptom:** 404 on API calls that should work
**Fix:** Action items and agent endpoints have `/api/` prefix. Auth, projects, health do NOT. Check `config.py` API_ROUTES.

### 4. Shell escaping with curl
**Symptom:** JSON parse errors, malformed requests
**Fix:** Use Python `urllib` (in `lib/api.py`), never `curl` with inline JSON in bash. If you must use curl, use `--data-binary @-` with heredoc.

### 5. Port confusion
**Symptom:** Connection refused, wrong service
**Fix:** BE = 3456 (external) / 8000 (container). FE = 3000 (external) / 8080 (container). DB = 5432.

### 6. No test user exists
**Symptom:** 401 on login
**Fix:** Run `python boardroom-ai/e2e/setup.py` first. It creates user via `/test/create-user`.

### 7. Stale database
**Symptom:** Old schema, missing columns
**Fix:** `docker compose down -v && docker compose up -d` for full reset with all migrations.

### 8. JWT token expired
**Symptom:** 401 on previously-working requests
**Fix:** Re-run `setup.py`. Tokens last ~1 hour.

## Troubleshooting Decision Tree

```
Test failing?
├── 404 on API?
│   ├── Check API_ROUTES in config.py for correct path
│   ├── Check if router is registered in main.py
│   └── Check /api/ prefix (action-items, agent = yes; auth, projects = no)
├── 500 on API?
│   ├── Check docker compose logs backend
│   ├── Check if migration is mounted in docker-compose.yml
│   └── Try docker compose down -v && up -d
├── 401 on API?
│   ├── Run setup.py to create user and get fresh token
│   └── Check Authorization header format: "Bearer {token}"
├── Blank page in browser?
│   ├── Check FE route (singular /project/ not /projects/)
│   └── Check frontend container is running
├── Claude-in-Chrome not responding?
│   ├── Check Claude-in-Chrome extension is installed and active in Chrome
│   ├── Restart Claude Code to reload MCP
│   └── Verify Chrome browser is open
└── Tests return SKIP?
    └── YAML tests are agent-driven. Use lead-orchestrator E2E Suite Mode
        or e2e-qa-runner skill to execute them.
```

## Config Quick Reference

Always import from `boardroom-ai/e2e/config.py`:

| Key | Value |
|-----|-------|
| `BE_URL` | `http://localhost:3456` |
| `FE_URL` | `http://localhost:3000` |
| `DB_PORT` | `5432` |
| `TEST_EMAIL` | `e2e-agent@test.com` |
| FE routes | `/project/{id}` (SINGULAR), `/auth`, `/chat/{chatId}` |
| BE routes (no prefix) | `/auth/*`, `/projects/*`, `/health` |
| BE routes (/api/ prefix) | `/api/projects/{id}/action-items`, `/api/agent/*` |

## Cross-References

| Resource | Path |
|----------|------|
| YAML test schema | `boardroom-ai/e2e/schemas/test-case.schema.yaml` |
| Golden reference tests | `boardroom-ai/e2e/reference/golden-p0-tests.md` |
| Config (source of truth) | `boardroom-ai/e2e/config.py` |
| Session state | `boardroom-ai/e2e/.state/session.json` |
| Test cases | `boardroom-ai/e2e/tests/feat-XXX/` |
| QA output | `qa/e2e/` |
| Screenshots | `qa/e2e/screenshots/` |
