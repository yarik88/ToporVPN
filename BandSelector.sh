#!/bin/sh
#
# install-bands.sh - LTE band control via LuCI Custom Commands
# For OpenWrt 24+ with apk, ModemManager, sms_tool
# Tested on: Huasifei WH3000 Pro / Thales T99W175 (Snapdragon X55)
#
# Usage:
#   wget -O - https://raw.githubusercontent.com/USER/REPO/main/install-bands.sh | sh
# or:
#   curl -sSL https://raw.githubusercontent.com/USER/REPO/main/install-bands.sh | sh
#

set -e

MODEM_INDEX="${MODEM_INDEX:-1}"
AT_PORT="${AT_PORT:-/dev/ttyUSB2}"

echo "================================================"
echo "  LTE Band Control - LuCI installer"
echo "  Modem index: $MODEM_INDEX"
echo "  AT port:     $AT_PORT"
echo "================================================"
echo ""

# --- 1. Check prerequisites ---
echo "[1/5] Checking prerequisites..."

if ! command -v mmcli >/dev/null 2>&1; then
    echo "ERROR: mmcli not found. Install ModemManager first."
    exit 1
fi

if ! command -v sms_tool >/dev/null 2>&1; then
    echo "WARNING: sms_tool not found. Status/restart commands will fail."
fi

if ! command -v apk >/dev/null 2>&1; then
    echo "ERROR: apk not found. This script requires OpenWrt 24+ with apk."
    exit 1
fi

# --- 2. Install luci-app-commands ---
echo ""
echo "[2/5] Installing luci-app-commands..."
apk update >/dev/null 2>&1 || true
apk add luci-app-commands >/dev/null 2>&1 || {
    echo "Note: package may already be installed, continuing..."
}

# --- 3. Remove old band commands (idempotency) ---
echo ""
echo "[3/5] Cleaning old band commands..."

# Remove any existing command whose name starts with our marker (BAND:)
# Loop from the end to avoid index shift
i=0
while uci -q get "luci.@command[$i]" >/dev/null 2>&1; do
    i=$((i+1))
done
i=$((i-1))

while [ $i -ge 0 ]; do
    name=$(uci -q get "luci.@command[$i].name" 2>/dev/null || echo "")
    case "$name" in
        "[BAND]"*)
            uci -q delete "luci.@command[$i]"
            ;;
    esac
    i=$((i-1))
done

# --- 4. Add commands ---
echo ""
echo "[4/5] Adding band control commands..."

add_cmd() {
    local desc="$1"
    local cmd="$2"
    local param="$3"
    uci add luci command >/dev/null
    uci set "luci.@command[-1].name=$desc"
    uci set "luci.@command[-1].command=$cmd"
    if [ "$param" = "1" ]; then
        uci set "luci.@command[-1].param=1"
    fi
}

add_cmd "[BAND] 📡 Lock B1 (2100 MHz, clean)" \
        "mmcli -m $MODEM_INDEX --set-current-bands=eutran-1"

add_cmd "[BAND] 📡 Lock B3 (1800 MHz)" \
        "mmcli -m $MODEM_INDEX --set-current-bands=eutran-3"

add_cmd "[BAND] 📡 Lock B7 (2600 MHz)" \
        "mmcli -m $MODEM_INDEX --set-current-bands=eutran-7"

add_cmd "[BAND] 📡 Lock B20 (800 MHz, long range)" \
        "mmcli -m $MODEM_INDEX --set-current-bands=eutran-20"

add_cmd "[BAND] 📡 Lock B1+B7 (clean aggregation)" \
        "mmcli -m $MODEM_INDEX --set-current-bands=eutran-1,eutran-7"

add_cmd "[BAND] 📡 Lock B1+B3+B7+B20 (popular RU bands)" \
        "mmcli -m $MODEM_INDEX --set-current-bands=eutran-1,eutran-3,eutran-7,eutran-20"

add_cmd "[BAND] 🔓 Unlock ALL bands (for relocation)" \
        "mmcli -m $MODEM_INDEX --set-current-bands=any"

add_cmd "[BAND] 📊 Show signal status" \
        "sms_tool -d $AT_PORT at 'AT^ABAND?'; sms_tool -d $AT_PORT at 'AT^CA_INFO?'; sms_tool -d $AT_PORT at 'at^debug?' | grep -E 'lte_rsrp|lte_rsrq|lte_snr|lte_rssi'"

add_cmd "[BAND] 🔄 Restart modem (CFUN reset)" \
        "sms_tool -d $AT_PORT at 'AT+CFUN=1,1'"

add_cmd "[BAND] 📡 Set custom bands (input: eutran-1 / eutran-1,eutran-7 / any)" \
        "mmcli -m $MODEM_INDEX --set-current-bands=" \
        "1"

uci commit luci

# --- 5. Restart LuCI ---
echo ""
echo "[5/5] Restarting LuCI..."
/etc/init.d/uhttpd restart >/dev/null 2>&1

echo ""
echo "================================================"
echo "  ✓ Installation complete!"
echo "================================================"
echo ""
echo "Open LuCI in browser:"
echo "  System -> Custom Commands -> Dashboard"
echo ""
echo "Press Ctrl+Shift+R in browser to reload cache."
echo ""
echo "To uninstall, run:"
echo "  curl -sSL <YOUR_URL>/uninstall-bands.sh | sh"
echo ""
