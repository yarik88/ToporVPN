#!/bin/sh

MODEM=1

show_status() {
    echo ""
    echo "=== Current status ==="
    sms_tool -d /dev/ttyUSB2 at 'AT^ABAND?' 2>/dev/null
    echo ""
    sms_tool -d /dev/ttyUSB2 at 'AT^CA_INFO?' 2>/dev/null
    echo ""
    echo "Signal:"
    sms_tool -d /dev/ttyUSB2 at 'at^debug?' 2>/dev/null | grep -E "lte_rsrp|lte_rsrq|lte_snr|lte_rssi"
    echo ""
}

apply_bands() {
    echo ""
    echo "Applying: $1"
    mmcli -m $MODEM --set-current-bands=$1
    echo "Waiting 15 seconds for re-registration..."
    sleep 15
    show_status
}

clear
echo "================================"
echo "  LTE Band Control"
echo "  T99W175 / Huasifei WH3000"
echo "================================"
echo ""
echo "  1) B1 only  (2100 MHz) - clean, recommended"
echo "  2) B3 only  (1800 MHz) - was overloaded"
echo "  3) B7 only  (2600 MHz) - usually free"
echo "  4) B20 only (800 MHz)  - long range"
echo "  5) B1 + B3   (aggregation)"
echo "  6) B1 + B7   (clean aggregation)"
echo "  7) B1 + B3 + B7 + B20 (popular RU bands)"
echo ""
echo "  9) All bands (any) - for relocation"
echo ""
echo "  s) Show current status"
echo "  r) Restart modem (CFUN reset)"
echo "  q) Quit"
echo ""
printf "Choice: "
read choice

case "$choice" in
    1) apply_bands "eutran-1" ;;
    2) apply_bands "eutran-3" ;;
    3) apply_bands "eutran-7" ;;
    4) apply_bands "eutran-20" ;;
    5) apply_bands "eutran-1,eutran-3" ;;
    6) apply_bands "eutran-1,eutran-7" ;;
    7) apply_bands "eutran-1,eutran-3,eutran-7,eutran-20" ;;
    9) apply_bands "any" ;;
    s|S) show_status ;;
    r|R)
        echo "Restarting modem..."
        sms_tool -d /dev/ttyUSB2 at 'AT+CFUN=1,1'
        echo "Wait 30 seconds."
        ;;
    q|Q) echo "Exit."; exit 0 ;;
    *) echo "Invalid choice." ;;
esac

echo ""
echo "Done. Press Enter to exit."
read dummy
