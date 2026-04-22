#!/bin/sh
# === OpenWRT setup: hostname + frpc + podkop + wifi + lan ===

read -p "Введите ID роутера (число, например 99): " rid

[ -z "$rid" ] && echo "ID пустой" && exit 1
case "$rid" in
    ''|*[!0-9]*) echo "ID должен быть числом"; exit 1 ;;
esac

newname="id${rid}"
SSH_PORT=$((11000 + rid))
WEB_PORT=$((10000 + rid))
WIFI_PASS="88888888"
LAN_IP="192.168.99.1"

echo "→ $newname | ssh:$SSH_PORT | web:$WEB_PORT | lan:$LAN_IP"

# 1. Hostname
uci set system.@system[0].hostname="$newname"
uci set system.@system[0].timezone='MSK-3'
uci set system.@system[0].zonename='Europe/Moscow'
uci commit system
echo "$newname" > /proc/sys/kernel/hostname
/etc/init.d/system reload

# 2. frpc
opkg update
opkg install luci-i18n-frpc-ru
cat > /etc/config/frpc <<EOF
config init
        option stdout '1'
        option stderr '1'
        option user 'root'
        option group 'root'
        option respawn '1'

config conf 'common'
        option server_addr '178.57.218.45'
        option server_port '63334'
        option tls_enable 'true'
        option token '54701e79-ddec-4695-a36b-a8580afacdf7'
        option login_fail_exit 'false'
        option protocol 'tcp'

config conf 'ssh'
        option type 'tcp'
        option local_ip '127.0.0.1'
        option local_port '22'
        option remote_port '${SSH_PORT}'
        option name '${newname}-ssh'
        option use_encryption 'true'
        option use_compression 'false'

config conf
        option name '${newname}-web'
        option type 'tcp'
        option use_encryption 'true'
        option use_compression 'false'
        option local_ip '127.0.0.1'
        option local_port '80'
        option remote_port '${WEB_PORT}'
EOF
uci commit frpc
/etc/init.d/frpc enable
/etc/init.d/frpc restart

# 3. Podkop (авто 'y')
wget -O /tmp/podkop_install.sh https://raw.githubusercontent.com/itdoginfo/podkop/refs/heads/main/install.sh
yes y 2>/dev/null | sh /tmp/podkop_install.sh
rm -f /tmp/podkop_install.sh

# 4. WiFi
for s in $(uci show wireless | grep "=wifi-iface" | cut -d= -f1); do
    uci set ${s}.ssid="$newname"
    uci set ${s}.encryption='psk2'
    uci set ${s}.key="$WIFI_PASS"
    uci set ${s}.disabled='0'
    uci set ${s}.mode='ap'
done
for r in $(uci show wireless | grep "=wifi-device" | cut -d= -f1); do
    uci set ${r}.disabled='0'
done
uci commit wireless
wifi reload

# 5. LAN (последним — сессия оборвётся)
echo "⚠ Сейчас сменю LAN на $LAN_IP — переподключайся туда или через frpc 178.57.218.45:$SSH_PORT"
uci set network.lan.ipaddr="$LAN_IP"
uci set network.lan.netmask='255.255.255.0'
uci commit network
( sleep 2 && /etc/init.d/network restart ) &
exit 0
