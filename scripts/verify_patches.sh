#!/bin/bash
# =============================================================================
# n8n Enterprise Patch Verifier
# =============================================================================
# Verifies that the license patches are correctly applied and working.
# =============================================================================

set -e

CONTAINER="${1:-n8n}"
BASE_URL="${2:-}"
EMAIL="${3:-}"
PASSWORD="${4:-}"

echo "======================================"
echo " n8n Enterprise Patch Verifier"
echo "======================================"
echo ""

# --- Check 1: Patched file in container ---
echo "📋 Check 1: Verifying patched license.js in container..."
PATCH_COUNT=$(sudo docker exec "$CONTAINER" sh -c \
  "grep -c 'PATCHED' /usr/local/lib/node_modules/n8n/dist/license.js 2>/dev/null || echo 0")

if [ "$PATCH_COUNT" -ge "1" ]; then
    echo "   ✅ Found $PATCH_COUNT patched lines in container's license.js"
    sudo docker exec "$CONTAINER" sh -c \
      "grep -n 'PATCHED' /usr/local/lib/node_modules/n8n/dist/license.js"
else
    echo "   ❌ No patches found in container's license.js"
    echo "   The volume mount may not be working. Check docker-compose.yml volumes."
fi
echo ""

# --- Check 2: Container is running ---
echo "📋 Check 2: Container status..."
STATUS=$(sudo docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null)
if [ "$STATUS" = "running" ]; then
    echo "   ✅ Container '$CONTAINER' is running"
else
    echo "   ❌ Container '$CONTAINER' status: $STATUS"
fi
echo ""

# --- Check 3: API health ---
if [ -n "$BASE_URL" ]; then
    echo "📋 Check 3: API health check..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/healthz" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        echo "   ✅ n8n API responding (HTTP 200)"
    else
        echo "   ⚠️  n8n API returned HTTP $HTTP_CODE"
    fi
    echo ""
fi

# --- Check 4: Login and verify enterprise features ---
if [ -n "$BASE_URL" ] && [ -n "$EMAIL" ] && [ -n "$PASSWORD" ]; then
    echo "📋 Check 4: Verifying enterprise features via API..."
    COOKIE_FILE="/tmp/n8n_verify_cookies.txt"

    curl -s -c "$COOKIE_FILE" -X POST "$BASE_URL/rest/login" \
        -H "Content-Type: application/json" \
        -d "{\"emailOrLdapLoginId\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" > /dev/null

    SETTINGS=$(curl -s -b "$COOKIE_FILE" "$BASE_URL/rest/settings")

    PLAN=$(echo "$SETTINGS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('license',{}).get('planName','unknown'))" 2>/dev/null || echo "unknown")
    BANNER=$(echo "$SETTINGS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('showNonProdBanner','unknown'))" 2>/dev/null || echo "unknown")

    echo "   Plan Name     : $PLAN"
    echo "   Show Banner   : $BANNER"

    if [ "$PLAN" = "Enterprise" ]; then
        echo "   ✅ Enterprise plan confirmed!"
    else
        echo "   ⚠️  Plan is '$PLAN' (expected 'Enterprise')"
    fi

    if [ "$BANNER" = "False" ] || [ "$BANNER" = "false" ]; then
        echo "   ✅ Non-production banner is hidden"
    else
        echo "   ⚠️  Banner status: $BANNER"
    fi

    rm -f "$COOKIE_FILE"
    echo ""
fi

echo "======================================"
echo " VERIFICATION COMPLETE"
echo "======================================"
