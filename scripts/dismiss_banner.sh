#!/bin/bash
# =============================================================================
# n8n Production Banner Dismiss Script
# =============================================================================
# Dismisses the "This n8n instance is not licensed for production purposes"
# banner permanently by calling n8n's own REST API.
# The dismissal is saved to the database and persists across restarts.
#
# Usage: bash dismiss_banner.sh <base_url> <email> <password>
#   base_url  - Your n8n URL (e.g., https://my-n8n.duckdns.org)
#   email     - n8n owner email
#   password  - n8n owner password
#
# Example:
#   bash dismiss_banner.sh https://my-n8n.example.com admin@email.com MyPassword
# =============================================================================

set -e

BASE_URL="${1}"
EMAIL="${2}"
PASSWORD="${3}"

if [ -z "$BASE_URL" ] || [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
    echo "Usage: $0 <base_url> <email> <password>"
    echo "Example: $0 https://my-n8n.example.com admin@email.com MyPassword"
    exit 1
fi

# Remove trailing slash
BASE_URL="${BASE_URL%/}"
COOKIE_FILE="/tmp/n8n_session_cookies.txt"

echo "======================================"
echo " n8n Banner Dismiss"
echo "======================================"
echo ""
echo "URL   : $BASE_URL"
echo "Email : $EMAIL"
echo ""

# Step 1: Login
echo "🔑 Logging in..."
LOGIN_RESPONSE=$(curl -s -c "$COOKIE_FILE" \
    -X POST "$BASE_URL/rest/login" \
    -H "Content-Type: application/json" \
    -d "{\"emailOrLdapLoginId\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

if echo "$LOGIN_RESPONSE" | grep -q '"email"'; then
    echo "   ✅ Login successful"
else
    echo "   ❌ Login failed!"
    echo "   Response: $LOGIN_RESPONSE"
    exit 1
fi
echo ""

# Step 2: Dismiss the NON_PRODUCTION_LICENSE banner
echo "🚫 Dismissing non-production banner..."
DISMISS_RESPONSE=$(curl -s -b "$COOKIE_FILE" \
    -X POST "$BASE_URL/rest/owner/dismiss-banner" \
    -H "Content-Type: application/json" \
    -d '{"banner":"NON_PRODUCTION_LICENSE"}')

if [ "$DISMISS_RESPONSE" = "{}" ] || [ -z "$DISMISS_RESPONSE" ]; then
    echo "   ✅ Banner dismissed successfully!"
    echo "   Saved to database under key: ui.banners.dismissed"
    echo ""
    echo "   The banner will NOT appear again even after container restarts."
else
    echo "   ⚠️  Unexpected response: $DISMISS_RESPONSE"
fi

echo ""
echo "======================================"
echo " DONE ✅"
echo "======================================"

# Cleanup
rm -f "$COOKIE_FILE"
