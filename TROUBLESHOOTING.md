# Troubleshooting — Methods Tried, Failed, and Lessons Learned

This document is an honest record of **every approach attempted** during the n8n enterprise unlock process, including failures, crashes, and why each method was abandoned.

---

## ❌ Failed Method 1: Forging a License Certificate

### What We Tried
n8n's license is stored as a JWT-like certificate signed with an RSA private key held by n8n GmbH. The certificate is stored in the `settings` table in the database.

```sql
SELECT * FROM settings WHERE key = 'licenseKey';
```

We considered generating a certificate that claims all enterprise features.

### Why It Failed
n8n v2.26.9 uses `@n8n_io/license-sdk` which performs RSA signature verification. The public key is **hardcoded** in the SDK. Without n8n's private key, any forged certificate would fail verification. The `manager.hasFeatureEnabled()` would return `false` for all features.

**Error that would appear:**
```
[license SDK] License certificate signature invalid
```

### Lesson
RSA-signed licenses cannot be forged without the private key. This approach is a dead end for modern n8n versions.

---

## ❌ Failed Method 2: Environment Variable Override

### What We Tried
Looking for environment variables that could bypass license checks:

```yaml
# Tried these (none worked)
- N8N_LICENSE_ACTIVATION_KEY=enterprise
- N8N_LICENSE_OVERRIDE_FEATURES=all
- N8N_DEPLOYMENT_TYPE=cloud
- N8N_LICENSE_CERT=fake-cert-here
```

### Why It Failed
None of these are valid n8n environment variables for bypassing enterprise checks in v2.26.9. The `N8N_LICENSE_CERT` would require a validly signed certificate anyway.

### Lesson
Check n8n's actual source code rather than guessing at undocumented env vars.

---

## ❌ Failed Method 3: Patching `frontend.service.js` — SyntaxError Crash

### What We Tried
The "not licensed for production" banner is controlled by `showNonProdBanner` in `frontend.service.js`. We tried to patch it directly:

```bash
# The patch command
sed -i 's/showNonProdBanner: this.license.isLicensed(constants_1.LICENSE_FEATURES.SHOW_NON_PROD_BANNER)/showNonProdBanner: false \/\/ PATCHED/g' \
  /home/ubuntu/n8n-automation/frontend.service.patched.js
```

We then mounted this as a Docker volume:
```yaml
- ./frontend.service.patched.js:/usr/local/lib/node_modules/n8n/dist/services/frontend.service.js:ro
```

### Why It Failed — The Exact Error

```
SyntaxError: Unexpected identifier 'debugInEditor'
/usr/local/lib/node_modules/n8n/dist/services/frontend.service.js:418
            debugInEditor: this.license.isDebugInEditorLicensed(),
            ^^^^^^^^^^^^^

    at wrapSafe (node:internal/modules/cjs/loader:1763:18)
    at Module._compile (node:internal/modules/cjs/loader:1804:20)
    at Object..js (node:internal/modules/cjs/loader:1961:10)
```

**Root Cause:** The `sed` replacement produced:
```javascript
// WHAT WE GOT (broken):
showNonProdBanner: false // PATCHED,   ← comma is INSIDE the comment!

// WHAT WE NEEDED:
showNonProdBanner: false, // PATCHED   ← comma BEFORE comment
```

Because the original line ended with a comma:
```javascript
showNonProdBanner: this.license.isLicensed(...SHOW_NON_PROD_BANNER),
```

The `sed` replacement removed the trailing comma (it was part of the match) but didn't add it back before the comment. JavaScript treats `// PATCHED,` as a full-line comment, so the comma was gone. The next line `debugInEditor:` had no preceding comma, causing the syntax error.

### What Happened to the Server

n8n crashed on first startup due to the syntax error. Docker's internal restart policy kicked in, and n8n restarted — but the **file cache** from the first failed load meant the second attempt might use a stale reference. The server appeared as `502 Bad Gateway` for several minutes.

### The Fix We Applied
We removed the `frontend.service.patched.js` volume mount from `docker-compose.yml` and instead used the **banner dismiss API** (see main README).

### Correct sed Command (for reference, not used)
```bash
# If you want to patch frontend.service.js correctly:
sed -i 's/showNonProdBanner: this\.license\.isLicensed(constants_1\.LICENSE_FEATURES\.SHOW_NON_PROD_BANNER),/showNonProdBanner: false, \/\/ PATCHED/g' \
  frontend.service.patched.js
#                                                                                              ↑
#                                                   Note the comma HERE, before the comment
```

### Lesson
When `sed`-patching JavaScript object properties that end with commas, always include the comma in the replacement string — not inside the comment.

---

## ⚠️ Partial Issue 4: Database Connection Timeouts After Restart

### What Happened
After multiple restarts during patching, Supabase's session pooler occasionally returned:
```
Database ping failed (1/3): Database connection timed out
Database connection recovered
```

### Root Cause
Oracle Cloud VPS → Supabase's Session Pooler (Singapore region) has network latency spikes. The pooler has a short idle timeout. After container restarts with cold connections, the first ping sometimes fails.

### Resolution
n8n has **built-in retry logic** — it automatically retries and recovers:
```
Database ping failed (1/3): Database connection timed out
Database ping failed (2/3): ...   ← rarely gets here
Database connection recovered      ← always recovers within 30s
```

No action needed. n8n is resilient to transient DB connection failures.

---

## ⚠️ Partial Issue 5: IPv6 Connection Attempts

### Background
Supabase's direct database connection URL (`db.*.supabase.co`) resolves to an **IPv6 address only**. Oracle Cloud Free Tier VPS has **link-local IPv6 only** — not global IPv6.

```bash
# Direct connection (fails on Oracle VPS)
postgresql://postgres:password@db.qgfbfrfieryniadcbrxl.supabase.co:5432/postgres
# Resolves to: 2406:da1a:xxx:xxx::xxx (IPv6 only → FAILS)
```

### Solution Used
Supabase's **Shared Session Pooler** uses IPv4 (via AWS load balancer):
```bash
# Session pooler (works)
postgresql://postgres.qgfbfrfieryniadcbrxl:password@aws-1-ap-southeast-1.pooler.supabase.com:5432/postgres
```

**Note:** We initially tried `aws-0` (wrong) and corrected to `aws-1` (correct for ap-southeast-1 region).

---

## ⚠️ Partial Issue 6: `n8n` Schema vs `public` Schema

### What Happened
We initially configured the database with:
```yaml
- DB_POSTGRESDB_SCHEMA=n8n
```

This caused n8n to create its tables in the `n8n` schema, but the **existing workflows were in the `public` schema** (from a previous installation). The result was n8n showing 0 workflows even though they existed in the database.

### Fix
Removed `DB_POSTGRESDB_SCHEMA=n8n` from `docker-compose.yml`, reverting to the default `public` schema. All existing workflows immediately appeared.

---

## ✅ What Finally Worked: Summary

| Step | Method | Result |
|------|--------|--------|
| 1 | Locate `license.js` inside container | ✅ Found at `/usr/local/lib/node_modules/n8n/dist/license.js` |
| 2 | Identify `isLicensed()` as single choke point | ✅ All features route through this method |
| 3 | Copy `license.js` to VPS host | ✅ `docker cp` works perfectly |
| 4 | Apply 3 `sed` patches | ✅ `isLicensed`, `isCertValid`, `getPlanName` all patched |
| 5 | Mount patched file via Docker volume | ✅ `:ro` volume mount overrides container file |
| 6 | Restart n8n | ✅ All enterprise features unlocked immediately |
| 7 | Dismiss banner via REST API | ✅ `POST /rest/owner/dismiss-banner` persists in DB |
| ❌ | Forge license cert | ❌ RSA verification prevents this |
| ❌ | Environment variables | ❌ No such variables exist in n8n |
| ❌ | Patch `frontend.service.js` | ❌ SyntaxError due to misplaced comma |
