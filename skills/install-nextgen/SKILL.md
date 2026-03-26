---
name: install-nextgen
description: Set up Boards Cloud local development (backend + frontend) from scratch on macOS. Handles prerequisites, cloning, building, OIDC config, and verification. Invoke when someone says "set up nextgen", "install boards cloud", or "set up local dev".
argument-hint: "[skip-prereqs]"
---

# Install Nextgen — Boards Cloud Local Dev Setup

## Overview

Fully automated setup of the Boards Cloud backend (.NET 10) and frontend (Angular 20) for local development on macOS. Handles all prerequisites, clones both repos, builds, starts services, and verifies login.

**Repos:**
- Backend: `DiligentCorp/boards-cloud-service` — .NET 10 monolith with TestContainers
- Frontend: `DiligentCorp/boards-cloud-client` — Angular 20 NX monorepo

**End state:** Backend at https://localhost:5050, Frontend at http://localhost:4200, login works with `john-admin / pwd`.

---

## Phase 1: Detect Environment

Run all checks in parallel. Do NOT ask the user yet — just gather facts.

```
Check                     | How                                        | Required
--------------------------|--------------------------------------------|----------------------------
.NET SDK                  | dotnet --version                           | 10.0.103 exactly
Node.js                   | node --version                             | >= 22.21.0, < 23
pnpm                      | pnpm --version                             | >= 10.23.0
nvm                       | command -v nvm                             | Needed if Node wrong version
Docker                    | docker info                                | Running, >= 4 CPU, >= 8GB RAM
Colima (if used)          | colima status                              | 4 CPU, 8 GiB RAM, 100 GiB disk
git                       | git --version                              | Any
GITHUB_TOKEN              | echo $GITHUB_TOKEN                         | Set and non-empty
~/.npmrc                  | cat ~/.npmrc                               | Has npm.pkg.github.com token
Port 5000                 | lsof -i :5000                              | Check if AirPlay occupies it
Port 5050                 | lsof -i :5050                              | Must be free
dotnet dev-certs trusted  | dotnet dev-certs https --check --trust     | Must be trusted
```

### Decision matrix after detection

Present ONE consolidated question to the user with everything that needs fixing. Group into:
- **Will install for you** (nvm, Node, pnpm, .NET SDK, dotnet-ef)
- **Needs your action** (GitHub PAT creation, SSO authorization, Colima restart)
- **Already satisfied** (skip silently)

---

## Phase 2: Install Prerequisites

Run independent installs in parallel where possible.

### .NET SDK 10.0.103

**PITFALL: `brew install dotnet` installs the WRONG version.** The `global.json` pins to `10.0.103` with `rollForward: disable` — any other version = hard build failure.

```bash
curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
chmod +x /tmp/dotnet-install.sh
/tmp/dotnet-install.sh --version 10.0.103 --install-dir ~/.dotnet
```

Add to `~/.zshrc` (idempotent — check before adding):
```bash
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"
```

Verify: `source ~/.zshrc && dotnet --version` must output `10.0.103`.

### Node.js 22.21.1 via nvm

**PITFALL: System Node is often v20. The frontend enforces `engine-strict=true` with `engines.node: ">=22.21.0 <23.0.0"`. Wrong version = hard install failure.**

```bash
# Install nvm if missing
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.zshrc

# Install and activate Node 22
nvm install 22.21.1
nvm alias default 22.21.1
```

### pnpm 10.23.0

**PITFALL: The frontend's `preinstall` script runs `only-allow pnpm` — npm/yarn = blocked.**

```bash
npm install -g pnpm@10.23.0
```

### Docker / Colima

**PITFALL: Colima defaults to 2 CPU / 2 GiB RAM. Backend TestContainers (Postgres + Keycloak + LocalStack) need at minimum 4 CPU / 8 GiB.**

```bash
# If Colima is running with insufficient resources:
colima stop
colima start --cpu 4 --memory 8 --disk 100
```

### dotnet-ef tool

```bash
dotnet tool install --global dotnet-ef
```

### HTTPS dev certificate

**PITFALL: Without this, the backend crashes during seeding with `UntrustedRoot` on internal gRPC calls. This is invisible until startup — the error says "The remote certificate is invalid" deep in the seeder logs.**

```bash
dotnet dev-certs https --trust
```

### GitHub PAT

**PITFALL: This is the #1 setup failure. The token must be SSO-authorized for DiligentCorp or ALL package downloads (NuGet + npm) return 403. A valid token that isn't SSO-authorized looks correct but fails silently.**

If user doesn't have a PAT, walk them through:
1. https://github.com/settings/tokens/new
2. Token type: **Classic**
3. Scopes: `write:packages`
4. After creation: **Configure SSO** → **Authorize** for **DiligentCorp**
5. Copy the `ghp_...` value

Configure it:
```bash
# ~/.zshrc
export GITHUB_TOKEN="ghp_TOKEN_HERE"

# ~/.npmrc (for @diligentcorp npm packages)
echo '//npm.pkg.github.com/:_authToken=ghp_TOKEN_HERE' >> ~/.npmrc
```

**Verify SSO authorization:** If `dotnet restore` or `pnpm install` returns 403, the PAT is NOT SSO-authorized. The user must go to GitHub → Settings → Tokens → click the token → Configure SSO → Authorize for DiligentCorp.

---

## Phase 3: Clone and Build

### Port 5000 / AirPlay conflict

**PITFALL: macOS Monterey+ runs AirPlay Receiver on port 5000. The backend's default port is 5000. You'll see the port "in use" but `curl` returns a mysterious 403 from Apple's AirTunes httpd — not your app.**

Detection: `lsof -i :5000 | grep ControlCenter` — if this returns a match, port 5000 is taken by AirPlay.

**Fix: Use port 5050 instead.** After cloning, modify `launchSettings.json` (see Phase 4).

Alternative: User disables AirPlay Receiver in System Settings > General > AirDrop & Handoff.

### Clone repos (parallel)

**PITFALL: `gh` CLI may fail with `x509: OSStatus -26276` TLS errors on some macOS setups. Use `git clone` directly.**

```bash
mkdir -p ~/Code/nextgen && cd ~/Code/nextgen

# Clone in parallel
git clone https://github.com/DiligentCorp/boards-cloud-service.git &
git clone https://github.com/DiligentCorp/boards-cloud-client.git &
wait
```

### Backend build

```bash
cd ~/Code/nextgen/boards-cloud-service
source ~/.zshrc  # ensure DOTNET_ROOT and GITHUB_TOKEN are set

dotnet restore   # ~2 min, requires GITHUB_TOKEN for DiligentCorp NuGet packages
dotnet build     # ~5 min first time, 17 warnings are normal (nullable refs, Sonar)
```

**If restore returns 403:** PAT is not SSO-authorized. See Phase 2 PAT section.

### Frontend build

```bash
cd ~/Code/nextgen/boards-cloud-client
source ~/.zshrc  # ensure nvm/Node are loaded

pnpm install     # ~3 min, 2,363 packages, requires ~/.npmrc token
```

**If install returns `ERR_PNPM_FETCH_403` on `@diligentcorp/*`:** PAT not SSO-authorized.
**If install fails with engine mismatch:** Wrong Node version. Run `nvm use 22.21.1`.

---

## Phase 4: Configure for Local Dev

### Backend port (if AirPlay conflict detected in Phase 3)

Edit `boards-cloud-service/src/Apps/Web.Api.Local/Properties/launchSettings.json`:

Change `applicationUrl` from `https://localhost:5000` to `https://localhost:5050`.

### Frontend local environment files

Edit BOTH of these files, setting port to 5050 (matching backend) and adding OIDC issuer validation overrides:

**`boards-cloud-client/src/apps/boards-frontend/src/environments/environment.local.ts`**
**`boards-cloud-client/src/apps/boards-csp/src/environments/environment.local.ts`**

In both files, ensure:
```typescript
auth: {
  // ... existing fields ...
  issValidationOff: true,
  strictIssuerValidationOnWellKnownRetrievalOff: true,
},
oidc: {
  authority: 'https://localhost:5050',  // must match backend port
},
domains: {
  serviceDiscoveryUrl: 'https://localhost:5050/disco',  // must match backend port
},
```

**PITFALL — OIDC Issuer Mismatch:** The backend proxies `/.well-known/openid-configuration` from its Keycloak TestContainer but passes through raw JSON. The discovery doc contains `issuer: "http://127.0.0.1:{random_port}/realms/{random_prefix}"` which doesn't match the frontend's configured `authority: "https://localhost:5050"`. The `angular-auth-oidc-client` library validates this match by default and throws console errors. The two flags above disable this validation for local dev only.

### Auth type interface

If the `Environment` type doesn't already include `issValidationOff` and `strictIssuerValidationOnWellKnownRetrievalOff` in the `Auth` interface, add them as optional fields:

**`boards-cloud-client/src/libs/core/core/src/interfaces/environment/environment.type.ts`**
```typescript
interface Auth {
  // ... existing fields ...
  issValidationOff?: boolean;
  strictIssuerValidationOnWellKnownRetrievalOff?: boolean;
}
```

These flow through `auth.config.ts` (`...environment.auth` spread) → `authentication-providers.ts` (`...authConfig.config` spread) → `angular-auth-oidc-client`'s `OpenIdConfiguration`.

---

## Phase 5: Start Services

### Terminal 1 — Backend

```bash
cd ~/Code/nextgen/boards-cloud-service
source ~/.zshrc
dotnet run --project src/Apps/Web.Api.Local/Web.Api.Local.csproj
```

This takes ~50-60 seconds. It automatically:
- Starts PostgreSQL 16.4, Keycloak 23.0.7, LocalStack 4.12 via TestContainers
- Runs EF Core migrations
- Seeds test data (2 orgs, 60 books, test users)

**Wait for:** `Now listening on: https://localhost:5050` in the console output.

Verify: `curl -sk https://localhost:5050/swagger | head -1` should return HTML.

### Terminal 2 — Frontend

```bash
cd ~/Code/nextgen/boards-cloud-client/src
source ~/.zshrc
pnpm run serve:fe:local
```

This takes ~90-100 seconds to compile. Wait for `Local: http://localhost:4200` in output.

---

## Phase 6: Verify

Run these checks to confirm everything works:

```
Check                                    | Command                                                           | Expected
-----------------------------------------|-------------------------------------------------------------------|---------------------------
Backend Swagger                          | curl -sk https://localhost:5050/swagger \| head -1                 | HTML content
OIDC Discovery                           | curl -sk https://localhost:5050/.well-known/openid-configuration  | JSON with issuer field
Service Discovery                        | curl -sk -X POST https://localhost:5050/disco -H 'Content-Type: application/json' -d '{"organizationId":"x","source":"platform"}' | JSON with regionData
Keycloak Users                           | curl -sk https://localhost:5050/keycloak/users \| python3 -m json.tool | JSON array with john-admin
Token Grant                              | curl -s -X POST "$(curl -sk https://localhost:5050/.well-known/openid-configuration \| python3 -c 'import sys,json;print(json.load(sys.stdin)["token_endpoint"])')" -d 'grant_type=password&client_id=boards-cloud&username=john-admin&password=pwd&scope=openid email membership' | access_token in response
Frontend loads                           | curl -s http://localhost:4200 \| head -1                          | <!doctype html>
```

### Browser verification

1. Open http://localhost:4200
2. If browser shows cert warning for `https://localhost:5050`, visit that URL first and accept the certificate
3. The app should redirect to Keycloak login at a URL like:
   `http://127.0.0.1:{random_port}/realms/{random_prefix}/protocol/openid-connect/auth?client_id=boards-cloud&redirect_uri=...`
   This is normal — Keycloak runs in a TestContainer with a random port and realm prefix each restart.
4. Enter credentials on the Keycloak login form:
   - **Username:** `john-admin`
   - **Password:** `pwd`
5. Should redirect back to `http://localhost:4200` and show the Boards Cloud dashboard

### Test users

| Username    | Password | Role  |
|-------------|----------|-------|
| john-admin  | pwd      | Admin |
| jane-admin  | pwd      | Admin |
| john-doe    | pwd      | User  |
| jane-doe    | pwd      | User  |

---

## Pitfall Reference (quick lookup)

| # | Symptom | Root Cause | Fix |
|---|---------|-----------|-----|
| 1 | `dotnet build` fails with SDK version error | `global.json` pins `10.0.103` with `rollForward: disable` | Use `dotnet-install.sh --version 10.0.103`, never brew |
| 2 | `pnpm install` fails with engine error | Node version < 22, `engine-strict=true` | `nvm install 22.21.1` |
| 3 | 403 on NuGet restore or pnpm install | GitHub PAT not SSO-authorized for DiligentCorp | GitHub Settings → Token → Configure SSO → Authorize |
| 4 | Port 5000 returns 403 or hangs on HTTPS | macOS AirPlay Receiver | Use port 5050 or disable AirPlay |
| 5 | Backend crashes with `UntrustedRoot` | Dev HTTPS cert not trusted | `dotnet dev-certs https --trust` |
| 6 | Frontend console: OIDC issuer mismatch | Keycloak internal URL ≠ configured authority | `issValidationOff: true` in local env |
| 7 | Colima containers OOM | Default 2GB insufficient | `colima start --cpu 4 --memory 8` |
| 8 | `gh` CLI TLS error (x509) | macOS keychain issue | Use `git clone` directly |
| 9 | `only-allow pnpm` error | Used npm/yarn instead of pnpm | `pnpm install` only |
| 10 | Missing exports on frontend serve | Barrel files not generated | `pnpm run generate:index` from `src/` |

---

## Architecture Notes (for context, not setup)

- **Backend** uses TestContainers — no docker-compose. Containers are started programmatically on `dotnet run` and cleaned up on exit. Ports are random each run.
- **Keycloak realm** gets a random prefix (e.g., `8545a8`). The realm name and port change every backend restart.
- **OIDC flow**: Frontend fetches discovery from backend proxy → browser redirects to Keycloak → user logs in → Keycloak redirects back with auth code → frontend exchanges code at Keycloak token endpoint (CORS allowed from `http://localhost:4200`).
- **Service discovery** (`/disco`): Frontend POSTs here to get the backend URL, WebSocket URL, etc. No auth required locally.
- **Backend token validation** uses the real Keycloak URL as Authority (correct). Only the frontend has the issuer mismatch because its configured authority is the proxy URL.

---

## Useful Commands

```bash
# Backend
dotnet run --project src/Apps/Web.Api.Local/Web.Api.Local.csproj     # Start backend
curl -sk https://localhost:5050/swagger                                # Swagger UI
curl -sk https://localhost:5050/keycloak/users/ui                      # Keycloak users (HTML)

# Frontend
cd boards-cloud-client/src
pnpm run serve:fe:local     # Local backend mode
pnpm run serve:boards-fe    # Remote backend mode
pnpm run generate:index     # Generate barrel files (run if missing exports)
pnpm run build:fe           # Production build
pnpm run test:all           # Run all tests

# Debug
lsof -i :5050               # Check what's on backend port
lsof -i :4200               # Check what's on frontend port
curl -sk https://localhost:5050/.well-known/openid-configuration | python3 -m json.tool   # OIDC discovery
docker ps                   # See TestContainers
```
