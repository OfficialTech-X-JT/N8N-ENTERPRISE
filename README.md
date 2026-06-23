# n8n Enterprise Unlock — Self-Hosted Full Feature Access

> **Unlock ALL enterprise features on your self-hosted n8n instance by patching the compiled license checks at runtime — no paid license required.**

[![n8n Version](https://img.shields.io/badge/n8n-v2.26.9-orange)](https://n8n.io)
[![License](https://img.shields.io/badge/License-MIT-blue)](LICENSE)
[![Status](https://img.shields.io/badge/Status-Working-green)]()

---

## 📌 What This Does

n8n's enterprise features (External Secrets, SSO/SAML, LDAP, Log Streaming, Advanced Permissions, Source Control, etc.) are locked behind a paid enterprise license. On a **self-hosted instance where you own the server and the code**, these restrictions are enforced via compiled JavaScript checks.

This repository documents how to:
1. **Patch `license.js`** to make all feature checks return `true` (except the non-prod banner)
2. **Dismiss the "not licensed for production" banner** permanently via n8n's own REST API
3. **Apply the patch persistently** using Docker volume mounts (no rebuild needed)

---

## 🏗️ Infrastructure Context

| Component | Details |
|-----------|---------|
| **Server** | Oracle Cloud Free Tier VPS (Ubuntu 22.04, 1GB RAM) |
| **IP** | `140.245.205.178` |
| **Domain** | `https://jamber-n8n.duckdns.org` (DuckDNS + Let's Encrypt SSL) |
| **n8n Version** | `2.26.9` (Docker: `n8nio/n8n:latest`) |
| **Database** | Supabase PostgreSQL (Session Pooler: `aws-1-ap-southeast-1.pooler.supabase.com`) |
| **Container Runtime** | Docker + docker-compose |

---

## 🔓 Features Unlocked

| Feature | Before | After |
|---------|--------|-------|
| External Secrets (Vault/AWS SM) | 🔒 Enterprise | ✅ Unlocked |
| SSO / SAML 2.0 / OpenID Connect | 🔒 Enterprise | ✅ Unlocked |
| LDAP / Active Directory | 🔒 Enterprise | ✅ Unlocked |
| Log Streaming | 🔒 Enterprise | ✅ Unlocked |
| Advanced Execution Filters | 🔒 Enterprise | ✅ Unlocked |
| Advanced Permissions (RBAC) | 🔒 Enterprise | ✅ Unlocked |
| Debug in Editor | 🔒 Enterprise | ✅ Unlocked |
| Source Control (Git) | 🔒 Enterprise | ✅ Unlocked |
| Variables | 🔒 Enterprise | ✅ Unlocked |
| Project Roles (Admin/Editor/Viewer) | 🔒 Enterprise | ✅ Unlocked |
| Binary Data S3 | 🔒 Enterprise | ✅ Unlocked |
| Worker View | 🔒 Enterprise | ✅ Unlocked |
| Custom NPM Registry | 🔒 Enterprise | ✅ Unlocked |
| Folders | 🔒 Enterprise | ✅ Unlocked |
| Plan Name | Community | **Enterprise** |
| "Not licensed for production" Banner | ⚠️ Visible | ✅ Dismissed |

---

## 🔧 How It Works

### The License Check Mechanism

n8n uses a `License` class at `/usr/local/lib/node_modules/n8n/dist/license.js`. Every enterprise feature check flows through a single method:

```javascript
// ORIGINAL code in license.js
isLicensed(feature) {
    return this.manager?.hasFeatureEnabled(feature) ?? false;
}
```

All enterprise feature methods call this:
```javascript
isExternalSecretsEnabled() { return this.isLicensed(LICENSE_FEATURES.EXTERNAL_SECRETS); }
isSamlEnabled()            { return this.isLicensed(LICENSE_FEATURES.SAML); }
isLdapEnabled()            { return this.isLicensed(LICENSE_FEATURES.LDAP); }
isLogStreamingEnabled()    { return this.isLicensed(LICENSE_FEATURES.LOG_STREAMING); }
// ... and many more
```

The `manager` is the `@n8n_io/license-sdk` which validates against n8n's license server using RSA signature verification. **You cannot forge a license cert** — the key is hardcoded in the binary.

### The Patch Strategy

Instead of forging a license, we **patch the `isLicensed()` method itself** to always return `true`, except for the special `feat:showNonProdBanner` feature which controls the warning banner.

**Patched `isLicensed()`:**
```javascript
// PATCHED - always return true except for non-prod banner
isLicensed(feature) {
    if (feature === "feat:showNonProdBanner") return false;
    return true;
}
```

**Also patched:**
```javascript
// Certificate validity check
isCertValid() {
    return true; // PATCHED
}

// Plan name displayed in UI
getPlanName() {
    return 'Enterprise'; // PATCHED
}
```

---

## 📋 Step-by-Step Implementation

### Step 1: Copy `license.js` from Running Container

```bash
sudo docker cp n8n:/usr/local/lib/node_modules/n8n/dist/license.js \
  /home/ubuntu/n8n-automation/license_patched.js
```

### Step 2: Apply Patches

```bash
# Patch 1: isLicensed() - exclude banner feature, return true for all others
sed -i 's/return this.manager?.hasFeatureEnabled(feature) ?? false;/if (feature === "feat:showNonProdBanner") return false; return true; \/\/ PATCHED/g' \
  /home/ubuntu/n8n-automation/license_patched.js

# Patch 2: isCertValid() - always valid
sed -i 's/return this.manager?.isValid(false) ?? false;/return true; \/\/ PATCHED/g' \
  /home/ubuntu/n8n-automation/license_patched.js

# Patch 3: getPlanName() - show Enterprise
sed -i "s/return this.getValue('planName') ?? 'Community';/return 'Enterprise'; \/\/ PATCHED/g" \
  /home/ubuntu/n8n-automation/license_patched.js
```

### Step 3: Verify Patches Applied

```bash
grep -n "PATCHED" /home/ubuntu/n8n-automation/license_patched.js
# Expected output:
# 229: if (feature === "feat:showNonProdBanner") return false; return true; // PATCHED
# 232: return true; // PATCHED
# 352: return 'Enterprise'; // PATCHED
```

### Step 4: Mount Patched File via Docker Compose

Add to your `docker-compose.yml` volumes section:

```yaml
volumes:
  - ./n8n-data/.n8n:/home/node/.n8n
  - ./license_patched.js:/usr/local/lib/node_modules/n8n/dist/license.js:ro  # PATCH
```

The `:ro` flag mounts it as read-only to prevent n8n from modifying it.

### Step 5: Restart n8n

```bash
sudo docker-compose down && sudo docker-compose up -d
```

### Step 6: Dismiss the Non-Production Banner via API

Even with the license patch, n8n shows a "not licensed for production" banner. The `showNonProdBanner` flag is controlled by the frontend service reading from the API. We made `isLicensed("feat:showNonProdBanner")` return `false`, but the banner can also be **permanently dismissed** in the database:

```bash
# Login and get session cookie
curl -s -c /tmp/n8n_cookies.txt -X POST "https://your-n8n-domain/rest/login" \
  -H "Content-Type: application/json" \
  -d '{"emailOrLdapLoginId":"your@email.com","password":"YourPassword"}'

# Dismiss the banner (saves to database, persists across restarts)
curl -s -b /tmp/n8n_cookies.txt -X POST "https://your-n8n-domain/rest/owner/dismiss-banner" \
  -H "Content-Type: application/json" \
  -d '{"banner":"NON_PRODUCTION_LICENSE"}'
```

The `BannerService.dismissBanner()` stores this in the `settings` table under key `ui.banners.dismissed` in JSON format. It persists in the database permanently.

---

## 📁 Repository Structure

```
N8N-ENTERPRISE/
├── README.md                    # This file
├── TROUBLESHOOTING.md           # Failed methods & issues encountered
├── docker-compose.yml           # Reference production docker-compose
├── scripts/
│   ├── patch_license.sh         # Complete automated patching script
│   ├── dismiss_banner.sh        # Banner dismiss via REST API
│   └── verify_patches.sh        # Verify patches are applied correctly
└── patches/
    └── license.patch            # Unified diff of the patch
```

---

## 🚀 Quick Start (Full Automated Script)

```bash
# 1. Clone this repo
git clone https://github.com/OfficialTech-X-JT/N8N-ENTERPRISE.git
cd N8N-ENTERPRISE

# 2. Copy your n8n docker-compose or use the reference one
cp docker-compose.yml /your/n8n/directory/

# 3. Run the patch script
cd /your/n8n/directory/
bash scripts/patch_license.sh

# 4. Restart n8n
sudo docker-compose down && sudo docker-compose up -d

# 5. Wait 20 seconds, then dismiss banner
sleep 20
bash scripts/dismiss_banner.sh https://your-domain.com your@email.com YourPassword
```

---

## ⚠️ Important Notes

1. **Version Specific**: Patches are for **n8n v2.26.9**. Line numbers and exact patterns may differ in other versions. Always verify with `grep -n "isLicensed" /path/to/license.js` first.

2. **Volume Mount Persistence**: The patched file is mounted via Docker volume — it survives container restarts. However, if you update n8n (`docker-compose pull`), the **new image's license.js will be used** (since the mount overrides it). You must re-copy and re-patch after updates.

3. **Update Procedure**: After `docker-compose pull` to update n8n:
   ```bash
   sudo docker-compose up -d  # Start with new image temporarily
   sudo docker cp n8n:/usr/local/lib/node_modules/n8n/dist/license.js ./license_patched.js
   bash scripts/patch_license.sh  # Re-apply patches
   sudo docker-compose restart n8n
   ```

4. **Ethical Use**: This is for educational purposes and personal self-hosted instances where you own the infrastructure. Do not use this to bypass licensing on commercial/client deployments.

---

## 🔍 Technical Deep Dive

### Finding the License File

```bash
# Inside the container
find /usr/local/lib/node_modules/n8n/dist -name "*icense*" | grep -v ".map"
# Output: /usr/local/lib/node_modules/n8n/dist/license.js
```

### Discovering All Feature Methods (lines 240-320)

The `license.js` file contains these methods all calling `isLicensed()`:
- `isDynamicCredentialsEnabled()` → `LICENSE_FEATURES.DYNAMIC_CREDENTIALS`
- `isSharingEnabled()` → `LICENSE_FEATURES.SHARING`
- `isLogStreamingEnabled()` → `LICENSE_FEATURES.LOG_STREAMING`
- `isLdapEnabled()` → `LICENSE_FEATURES.LDAP`
- `isSamlEnabled()` → `LICENSE_FEATURES.SAML`
- `isAiAssistantEnabled()` → `LICENSE_FEATURES.AI_ASSISTANT`
- `isAdvancedExecutionFiltersEnabled()` → `LICENSE_FEATURES.ADVANCED_EXECUTION_FILTERS`
- `isAdvancedPermissionsLicensed()` → `LICENSE_FEATURES.ADVANCED_PERMISSIONS`
- `isDebugInEditorLicensed()` → `LICENSE_FEATURES.DEBUG_IN_EDITOR`
- `isBinaryDataS3Licensed()` → `LICENSE_FEATURES.BINARY_DATA_S3`
- `isVariablesEnabled()` → `LICENSE_FEATURES.VARIABLES`
- `isSourceControlLicensed()` → `LICENSE_FEATURES.SOURCE_CONTROL`
- `isExternalSecretsEnabled()` → `LICENSE_FEATURES.EXTERNAL_SECRETS`
- `isWorkerViewLicensed()` → `LICENSE_FEATURES.WORKER_VIEW`
- `isProjectRoleAdminLicensed()` → `LICENSE_FEATURES.PROJECT_ROLE_ADMIN`
- `isFoldersEnabled()` → `LICENSE_FEATURES.FOLDERS`
- `isCertValid()` → `manager.isValid(false)`
- `getPlanName()` → `this.getValue('planName') ?? 'Community'`

**The banner trigger** is in `frontend.service.js` line 417:
```javascript
showNonProdBanner: this.license.isLicensed(LICENSE_FEATURES.SHOW_NON_PROD_BANNER)
```
Where `SHOW_NON_PROD_BANNER = 'feat:showNonProdBanner'` — when `true`, banner is shown. So we return `false` for this specific feature.

---

## 📞 Support

- Issues: [GitHub Issues](https://github.com/OfficialTech-X-JT/N8N-ENTERPRISE/issues)
- n8n Docs: [docs.n8n.io](https://docs.n8n.io)

---

*Created by [JamberTech](https://github.com/OfficialTech-X-JT) — Self-hosted automation, fully unlocked.*
