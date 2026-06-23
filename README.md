# n8n Enterprise Unlock — Self-Hosted Full Feature Access

> **Unlock ALL enterprise features on any self-hosted n8n instance by patching the compiled license checks at runtime — no paid license required. Works on any VPS: Hostinger, DigitalOcean, Vultr, Linode, Oracle, AWS, etc.**

[![n8n Version](https://img.shields.io/badge/n8n-v2.26.9-orange)](https://n8n.io)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue)](LICENSE)
[![Status](https://img.shields.io/badge/Status-Working-brightgreen)]()
[![VPS](https://img.shields.io/badge/VPS-Universal-purple)]()

---

## 📌 What This Does

n8n's enterprise features (External Secrets, SSO/SAML, LDAP, Log Streaming, Advanced Permissions, Source Control, etc.) are locked behind a paid enterprise license. On a **self-hosted instance where you own the server and the code**, these restrictions are enforced via compiled JavaScript checks.

This repository documents how to:
1. **Patch `license.js`** to make all feature checks return `true` (except the non-prod banner)
2. **Dismiss the "not licensed for production" banner** permanently via n8n's own REST API
3. **Apply the patch persistently** using Docker volume mounts (no rebuild, no custom image needed)

---

## 🖥️ Compatible VPS Providers

| Provider | IPv4 | Works Out of Box |
|----------|------|-----------------|
| **Hostinger VPS** | ✅ | ✅ Yes |
| **DigitalOcean Droplet** | ✅ | ✅ Yes |
| **Vultr** | ✅ | ✅ Yes |
| **Linode / Akamai** | ✅ | ✅ Yes |
| **Hetzner** | ✅ | ✅ Yes |
| **AWS EC2** | ✅ | ✅ Yes |
| **Oracle Cloud Free Tier** | ✅* | ⚠️ IPv6-only issue with Supabase direct URL — use Session Pooler |
| **Google Cloud** | ✅ | ✅ Yes |

> **Oracle Cloud Note:** Oracle Free Tier VMs have link-local IPv6 only. If using Supabase, use the **Session Pooler** URL (`aws-X-region.pooler.supabase.com`) instead of the direct `db.*.supabase.co` URL which is IPv6-only.

---

## 🔓 Features Unlocked

| Feature | Before | After |
|---------|--------|-------|
| External Secrets (HashiCorp Vault / AWS SM / GCP SM) | 🔒 Enterprise | ✅ Unlocked |
| SSO / SAML 2.0 / OpenID Connect | 🔒 Enterprise | ✅ Unlocked |
| LDAP / Active Directory | 🔒 Enterprise | ✅ Unlocked |
| Log Streaming (to Splunk, Datadog, etc.) | 🔒 Enterprise | ✅ Unlocked |
| Advanced Execution Filters | 🔒 Enterprise | ✅ Unlocked |
| Advanced Permissions (RBAC) | 🔒 Enterprise | ✅ Unlocked |
| Debug in Editor | 🔒 Enterprise | ✅ Unlocked |
| Source Control (Git Integration) | 🔒 Enterprise | ✅ Unlocked |
| Variables | 🔒 Enterprise | ✅ Unlocked |
| Project Roles (Admin / Editor / Viewer) | 🔒 Enterprise | ✅ Unlocked |
| Binary Data via S3 | 🔒 Enterprise | ✅ Unlocked |
| Worker View | 🔒 Enterprise | ✅ Unlocked |
| Custom NPM Registry for Nodes | 🔒 Enterprise | ✅ Unlocked |
| Folders | 🔒 Enterprise | ✅ Unlocked |
| Plan Name shown in UI | Community | **Enterprise** |
| "Not licensed for production" Banner | ⚠️ Visible | ✅ Permanently Dismissed |

---

## 🏗️ Prerequisites

- A VPS running **Ubuntu 20.04 / 22.04** (or any Linux with Docker)
- **Docker** + **docker-compose** installed
- **n8n v2.26.9** running in Docker (other versions may need line number adjustments)
- A domain with SSL (Nginx + Let's Encrypt recommended) OR direct HTTP access

### Install Docker (if not already)
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
sudo apt install docker-compose -y
```

---

## 🔧 How It Works

### The License Check Mechanism

n8n uses a `License` class at `/usr/local/lib/node_modules/n8n/dist/license.js`. Every enterprise feature check flows through a single method:

```javascript
// ORIGINAL code in license.js (line ~229)
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
// ... and 12+ more
```

The `manager` is `@n8n_io/license-sdk` which validates via RSA signature against n8n's server. **You cannot forge a license cert** — the RSA public key is hardcoded in the SDK binary.

### The Patch Strategy

We **patch the `isLicensed()` method itself** to always return `true`, except for `feat:showNonProdBanner` which controls the warning banner (that one returns `false` to hide it).

**Patched code:**
```javascript
isLicensed(feature) {
    if (feature === "feat:showNonProdBanner") return false;
    return true; // PATCHED — all enterprise features enabled
}
```

The patched file is mounted into the running container via Docker volume — **no image rebuild needed**.

---

## 📋 Step-by-Step Implementation

### Step 1: SSH into your VPS

```bash
ssh user@YOUR_VPS_IP
# or with key:
ssh -i ~/.ssh/your_key.pem ubuntu@YOUR_VPS_IP
```

### Step 2: Make sure n8n is running

```bash
sudo docker ps | grep n8n
# Should show n8n container as "Up"
```

### Step 3: Copy `license.js` from the running container

```bash
cd /path/to/your/n8n/directory   # where your docker-compose.yml is

sudo docker cp n8n:/usr/local/lib/node_modules/n8n/dist/license.js \
  ./license_patched.js
```

> **Note:** Replace `n8n` with your container name if different. Check with `sudo docker ps`.

### Step 4: Apply the 3 patches

```bash
# Patch 1: isLicensed() — always true except banner
sed -i 's/return this.manager?.hasFeatureEnabled(feature) ?? false;/if (feature === "feat:showNonProdBanner") return false; return true; \/\/ PATCHED/g' \
  ./license_patched.js

# Patch 2: isCertValid() — always valid
sed -i 's/return this.manager?.isValid(false) ?? false;/return true; \/\/ PATCHED/g' \
  ./license_patched.js

# Patch 3: getPlanName() — show Enterprise
sed -i "s/return this.getValue('planName') ?? 'Community';/return 'Enterprise'; \/\/ PATCHED/g" \
  ./license_patched.js
```

### Step 5: Verify patches applied (should show 3 lines)

```bash
grep -n "PATCHED" ./license_patched.js
# Expected output:
# 229:   if (feature === "feat:showNonProdBanner") return false; return true; // PATCHED
# 232:   return true; // PATCHED
# 352:   return 'Enterprise'; // PATCHED
```

### Step 6: Add volume mount to `docker-compose.yml`

```yaml
volumes:
  - ./n8n-data/.n8n:/home/node/.n8n
  - ./license_patched.js:/usr/local/lib/node_modules/n8n/dist/license.js:ro  # ← ADD THIS
```

### Step 7: Restart n8n

```bash
sudo docker-compose down && sudo docker-compose up -d
```

### Step 8: Dismiss the production banner (permanent)

Wait ~20 seconds for n8n to start, then:

```bash
# Replace with your actual values
N8N_URL="https://your-n8n-domain.com"
EMAIL="your@email.com"
PASSWORD="YourPassword"

# Login
curl -s -c /tmp/n8n_cookies.txt -X POST "$N8N_URL/rest/login" \
  -H "Content-Type: application/json" \
  -d "{\"emailOrLdapLoginId\":\"$EMAIL\",\"password\":\"$PASSWORD\"}"

# Dismiss banner (saves to database, persists across restarts)
curl -s -b /tmp/n8n_cookies.txt -X POST "$N8N_URL/rest/owner/dismiss-banner" \
  -H "Content-Type: application/json" \
  -d '{"banner":"NON_PRODUCTION_LICENSE"}'
# Expected output: {}
```

### Step 9: Verify everything works

Open your n8n URL → Settings → **External Secrets** — should show configuration form, not "Available on Enterprise plan".

---

## 🚀 One-Command Quick Start

Use the automated scripts in this repo:

```bash
# Clone
git clone https://github.com/OfficialTech-X-JT/N8N-ENTERPRISE.git

# Go to your n8n directory
cd /path/to/your/n8n/

# Run patcher
bash /path/to/N8N-ENTERPRISE/scripts/patch_license.sh n8n .

# Restart n8n
sudo docker-compose down && sudo docker-compose up -d

# Wait and dismiss banner
sleep 25
bash /path/to/N8N-ENTERPRISE/scripts/dismiss_banner.sh \
  https://your-n8n-domain.com \
  your@email.com \
  YourPassword

# Verify
bash /path/to/N8N-ENTERPRISE/scripts/verify_patches.sh n8n https://your-n8n-domain.com
```

---

## 📁 Repository Structure

```
N8N-ENTERPRISE/
├── README.md                    ← This file — full guide
├── TROUBLESHOOTING.md           ← Failed methods, crashes & lessons
├── LICENSE                      ← Apache 2.0
├── docker-compose.yml           ← Reference config (generic, all placeholders)
├── scripts/
│   ├── patch_license.sh         ← Automated patcher
│   ├── dismiss_banner.sh        ← Banner dismiss via REST API
│   └── verify_patches.sh        ← Verify everything is working
└── patches/
    └── license.patch            ← Unified diff of changes
```

---

## 🔄 After Updating n8n

When you run `docker-compose pull` to update n8n, the new image will have the **original unpatched** `license.js`. Re-apply the patch:

```bash
# Pull new image and start temporarily
sudo docker-compose pull && sudo docker-compose up -d

# Re-copy and re-patch
sudo docker cp n8n:/usr/local/lib/node_modules/n8n/dist/license.js ./license_patched.js
bash scripts/patch_license.sh n8n .

# Restart with patch applied
sudo docker-compose restart n8n
```

---

## ⚠️ Important Notes

1. **Version Specific**: Tested on **n8n v2.26.9**. Line numbers may differ in other versions. Always verify with `grep -n "isLicensed" ./license_patched.js` first.

2. **Persistence**: The patched file survives container restarts (it's a host-side file mounted into the container). Re-patching only needed after `docker pull`.

3. **Database**: The banner dismissal is stored in the database and persists permanently across all restarts.

4. **Ethical Use**: For personal self-hosted instances only. Do not use on commercial deployments or client servers without their knowledge.

---

## 🗄️ Database Options

| Database | Compatibility | Notes |
|----------|--------------|-------|
| SQLite | ✅ Default | Built-in, no setup. Fine for personal use. |
| PostgreSQL (local) | ✅ Recommended | Install on same VPS |
| PostgreSQL (Supabase) | ✅ Works | Use **Session Pooler** URL for IPv4 VPS compatibility |
| MySQL/MariaDB | ✅ Supported | Set `DB_TYPE=mysqldb` |

### Supabase Session Pooler URL format:
```
postgresql://postgres.YOUR_PROJECT_REF:YOUR_PASSWORD@aws-0-REGION.pooler.supabase.com:5432/postgres
```
> Use `aws-0` for most regions, `aws-1` for `ap-southeast-1`

---

## 📞 Contributing

PRs welcome! If you test this on a different n8n version, please open an issue with:
- n8n version
- Which line numbers the patterns appear on
- Whether the `sed` commands worked or needed adjustment

---

*Created by [JamberTech](https://github.com/OfficialTech-X-JT) — Apache 2.0 Licensed*
