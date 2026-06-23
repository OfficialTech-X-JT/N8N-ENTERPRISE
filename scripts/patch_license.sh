#!/bin/bash
# =============================================================================
# n8n Enterprise License Patcher
# =============================================================================
# Patches the compiled license.js in a running n8n Docker container to unlock
# all enterprise features without a paid license.
#
# Usage: bash patch_license.sh [container_name] [output_dir]
#   container_name  - Docker container name (default: n8n)
#   output_dir      - Where to save the patched file (default: current dir)
#
# Requirements: Docker, running n8n container
# Tested on: n8n v2.26.9
# =============================================================================

set -e

CONTAINER="${1:-n8n}"
OUTPUT_DIR="${2:-.}"
LICENSE_PATH="/usr/local/lib/node_modules/n8n/dist/license.js"
OUTPUT_FILE="$OUTPUT_DIR/license_patched.js"

echo "======================================"
echo " n8n Enterprise License Patcher"
echo "======================================"
echo ""
echo "Container  : $CONTAINER"
echo "Output Dir : $OUTPUT_DIR"
echo ""

# Check if container is running
if ! sudo docker inspect "$CONTAINER" &>/dev/null; then
    echo "❌ ERROR: Container '$CONTAINER' not found or not running"
    exit 1
fi

echo "✅ Container '$CONTAINER' is running"
echo ""

# Step 1: Copy license.js from container
echo "📋 Step 1: Copying license.js from container..."
sudo docker cp "$CONTAINER:$LICENSE_PATH" "$OUTPUT_FILE"
echo "   Saved to: $OUTPUT_FILE"
echo ""

# Step 2: Backup original
cp "$OUTPUT_FILE" "$OUTPUT_FILE.bak"
echo "💾 Backup saved: $OUTPUT_FILE.bak"
echo ""

# Step 3: Verify the target patterns exist
echo "🔍 Step 3: Verifying patch targets..."

if ! grep -q "return this.manager?.hasFeatureEnabled(feature) ?? false;" "$OUTPUT_FILE"; then
    echo "❌ ERROR: Could not find 'isLicensed' pattern in license.js"
    echo "   This patch may not be compatible with your n8n version."
    echo "   Check the file manually: grep -n 'isLicensed' $OUTPUT_FILE"
    exit 1
fi

if ! grep -q "return this.manager?.isValid(false) ?? false;" "$OUTPUT_FILE"; then
    echo "⚠️  WARNING: Could not find 'isCertValid' pattern — skipping that patch"
fi

if ! grep -q "return this.getValue('planName') ?? 'Community';" "$OUTPUT_FILE"; then
    echo "⚠️  WARNING: Could not find 'getPlanName' pattern — skipping that patch"
fi

echo "   ✅ Target patterns found"
echo ""

# Step 4: Apply patches
echo "🔧 Step 4: Applying patches..."

# Patch 1: isLicensed() - return true for all features except banner
sed -i "s/return this.manager?.hasFeatureEnabled(feature) ?? false;/if (feature === \"feat:showNonProdBanner\") return false; return true; \/\/ PATCHED/g" "$OUTPUT_FILE"
echo "   ✅ Patch 1/3: isLicensed() → always true (banner excluded)"

# Patch 2: isCertValid() - always valid
sed -i 's/return this.manager?.isValid(false) ?? false;/return true; \/\/ PATCHED/g' "$OUTPUT_FILE"
echo "   ✅ Patch 2/3: isCertValid() → always true"

# Patch 3: getPlanName() - show Enterprise
sed -i "s/return this.getValue('planName') ?? 'Community';/return 'Enterprise'; \/\/ PATCHED/g" "$OUTPUT_FILE"
echo "   ✅ Patch 3/3: getPlanName() → 'Enterprise'"
echo ""

# Step 5: Verify patches applied
echo "✅ Step 5: Verifying patches..."
PATCH_COUNT=$(grep -c "PATCHED" "$OUTPUT_FILE" 2>/dev/null || echo "0")

if [ "$PATCH_COUNT" -lt 1 ]; then
    echo "❌ ERROR: Patches do not appear to have been applied!"
    echo "   Check $OUTPUT_FILE manually"
    exit 1
fi

echo "   Found $PATCH_COUNT patched lines:"
grep -n "PATCHED" "$OUTPUT_FILE"
echo ""

# Step 6: Instructions
echo "======================================"
echo " NEXT STEPS"
echo "======================================"
echo ""
echo "1. Add this volume mount to your docker-compose.yml:"
echo ""
echo "   volumes:"
echo "     - ./license_patched.js:$LICENSE_PATH:ro"
echo ""
echo "2. Restart n8n:"
echo "   sudo docker-compose down && sudo docker-compose up -d"
echo ""
echo "3. After 20 seconds, dismiss the production banner:"
echo "   bash dismiss_banner.sh https://your-n8n-domain.com your@email.com YourPassword"
echo ""
echo "======================================"
echo " PATCH COMPLETE ✅"
echo "======================================"
