#!/bin/sh
# === OpenWRT setup: passwd + hostname + frpc + sftp + podkop + wifi + lan ===

# Перенаправляем stdin прямо на терминал — спасает от ситуации, когда
# Termius/iTerm пастит сниппет с лишним \n, и первый read хватает пустую строку
[ -e /dev/tty ] && exec </dev/tty

# Сливаем буферизованный ввод (если что-то залетело от вставки)
while read -r -t 1 _ 2>/dev/null; do :; done

# ────────────────────────────────────────────────────────────────────
#   ЛОГО
# ────────────────────────────────────────────────────────────────────
cat <<'BANNER'

   ████████╗ ██████╗ ██████╗  ██████╗ ██████╗     ██╗   ██╗██████╗ ███╗   ██╗
   ╚══██╔══╝██╔═══██╗██╔══██╗██╔═══██╗██╔══██╗    ██║   ██║██╔══██╗████╗  ██║
      ██║   ██║   ██║██████╔╝██║   ██║██████╔╝    ██║   ██║██████╔╝██╔██╗ ██║
      ██║   ██║   ██║██╔═══╝ ██║   ██║██╔══██╗    ╚██╗ ██╔╝██╔═══╝ ██║╚██╗██║
      ██║   ╚██████╔╝██║     ╚██████╔╝██║  ██║     ╚████╔╝ ██║     ██║ ╚████║
      ╚═╝    ╚═════╝ ╚═╝      ╚═════╝ ╚═╝  ╚═╝      ╚═══╝  ╚═╝     ╚═╝  ╚═══╝

          ┌──────────────────────────────────────────────────────────┐
          │   T O P O R   V P N   R O U T E R S                      │
          │                                                          │
          │   «Private internet • No logs • No borders»              │
          │                                                          │
          │   ⚡  Рубит блокировки как топор  ⚡                       │
          │   🛡  Свой приватный интернет под ключ                   │
          │   🌐  Подписка, сервер и роутер — всё в одном решении    │
          │                                                          │
          │        toporrubit.ru   •   @ToporVPN                     │
          └──────────────────────────────────────────────────────────┘

BANNER
sleep 1

# --- 1. Пароль root (САМЫМ ПЕРВЫМ!) ---
echo "[1/8] Установка пароля root = 88888888..."
yes "88888888" 2>/dev/null | passwd root >/dev/null 2>&1
echo "✓ root password установлен"

# --- Запрос ID ---
echo ""
# Ещё раз сливаем буфер на всякий случай (после passwd)
while read -r -t 1 _ 2>/dev/null; do :; done
read -p "Введите ID роутера (число 1-999, например 99): " rid
[ -z "$rid" ] && echo "✗ ID пустой" && exit 1
case "$rid" in
    ''|*[!0-9]*) echo "✗ ID должен быть числом"; exit 1 ;;
esac
if [ "$rid" -lt 1 ] || [ "$rid" -gt 999 ]; then
    echo "✗ ID должен быть в диапазоне 1-999 (введено: $rid)"
    exit 1
fi

# --- Проверка FRPC_TOKEN (токен НЕ хранится в публичном скрипте) ---
if [ -z "$FRPC_TOKEN" ]; then
    echo ""
    echo "✗ Переменная окружения FRPC_TOKEN не задана."
    echo "  Запускай через сниппет вида:"
    echo "    export FRPC_TOKEN=<токен> && wget ... && sh /tmp/setup.sh"
    exit 1
fi

newname="id${rid}"
SSH_PORT=$((11000 + rid))
WEB_PORT=$((10000 + rid))
LAN_IP="192.168.99.1"

# --- Запрос WiFi SSID и пароля (с дефолтами) ---
DEFAULT_SSID="$newname"
DEFAULT_WIFI_PASS="88888888"

echo ""
echo "--- WiFi ---"
echo "Enter — оставит дефолты (SSID: $DEFAULT_SSID, пароль: $DEFAULT_WIFI_PASS)"

# Чистим буфер перед вводом
while read -r -t 1 _ 2>/dev/null; do :; done

printf "Введите WiFi SSID [%s]: " "$DEFAULT_SSID"
read -r WIFI_SSID
[ -z "$WIFI_SSID" ] && WIFI_SSID="$DEFAULT_SSID"

# Пароль — с валидацией длины (WPA2-PSK требует 8..63 символов)
while :; do
    printf "Введите WiFi пароль (8-63 симв) [%s]: " "$DEFAULT_WIFI_PASS"
    read -r WIFI_PASS
    [ -z "$WIFI_PASS" ] && WIFI_PASS="$DEFAULT_WIFI_PASS"
    plen=$(printf %s "$WIFI_PASS" | wc -c)
    if [ "$plen" -ge 8 ] && [ "$plen" -le 63 ]; then
        break
    fi
    echo "  ✗ Пароль должен быть длиной 8-63 символа (введено $plen). Повтори."
done

echo ""
echo "============================================="
echo "  Hostname:   $newname"
echo "  frpc SSH:   $newname-ssh -> :$SSH_PORT"
echo "  frpc Web:   $newname-web -> :$WEB_PORT"
echo "  WiFi SSID:  $WIFI_SSID (2.4 + 5 ГГц)"
echo "  WiFi pass:  $WIFI_PASS"
echo "  LAN IP:     $LAN_IP"
echo "============================================="

# --- 2. Hostname + Timezone ---
echo ""
echo "[2/8] Hostname + Timezone..."
uci set system.@system[0].hostname="$newname"
uci set system.@system[0].timezone='MSK-3'
uci set system.@system[0].zonename='Europe/Moscow'
uci commit system
echo "$newname" > /proc/sys/kernel/hostname
/etc/init.d/system reload
echo "✓ Hostname: $newname, TZ: Europe/Moscow"

# --- 3. Установка пакетов (frpc + sftp + русский LuCI) ---
echo ""
echo "[3/8] opkg update + установка frpc, sftp и русского LuCI..."
opkg update
opkg install luci-i18n-base-ru luci-i18n-frpc-ru openssh-sftp-server

# Включаем русский язык веб-интерфейса LuCI
uci set luci.main.lang='ru' 2>/dev/null
uci commit luci 2>/dev/null
echo "✓ Пакеты установлены, язык LuCI: ru"

# --- 4. Конфиг frpc (домен router.toporrubit.ru) ---
echo ""
echo "[4/8] Настройка frpc..."
cat > /etc/config/frpc <<EOF
config init
        option stdout '1'
        option stderr '1'
        option user 'root'
        option group 'root'
        option respawn '1'

config conf 'common'
        option server_addr 'router.toporrubit.ru'
        option server_port '63334'
        option tls_enable 'true'
        option token '${FRPC_TOKEN}'
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

config conf 'web'
        option type 'tcp'
        option local_ip '127.0.0.1'
        option local_port '80'
        option remote_port '${WEB_PORT}'
        option name '${newname}-web'
        option use_encryption 'true'
        option use_compression 'false'
EOF
uci commit frpc
/etc/init.d/frpc enable
/etc/init.d/frpc restart
echo "✓ frpc -> router.toporrubit.ru (ssh:${SSH_PORT}, web:${WEB_PORT})"

# --- 5. Установка podkop (авто 'y' на вопрос про русский язык) ---
echo ""
echo "[5/8] Установка podkop..."
wget --no-check-certificate -O /tmp/podkop_install.sh \
    https://raw.githubusercontent.com/itdoginfo/podkop/refs/heads/main/install.sh
yes y 2>/dev/null | sh /tmp/podkop_install.sh
rm -f /tmp/podkop_install.sh
echo "✓ Podkop установлен"

# --- 6. Конфиг podkop ---
echo ""
echo "[6/8] Настройка podkop..."

# Базовый конфиг — БЕЗ urltest_proxy_links (их добавим через uci,
# чтобы спецсимволы в VLESS-ссылках не ломали heredoc)
cat > /etc/config/podkop <<'EOF'

config settings 'settings'
	option dns_type 'udp'
	option dns_server '77.88.8.8'
	option bootstrap_dns_server '8.8.8.8'
	option dns_rewrite_ttl '60'
	list source_network_interfaces 'br-lan'
	option enable_output_network_interface '0'
	option enable_badwan_interface_monitoring '0'
	option enable_yacd '0'
	option disable_quic '1'
	option update_interval '1d'
	option download_lists_via_proxy '0'
	option dont_touch_dhcp '0'
	option config_path '/etc/sing-box/config.json'
	option cache_path '/tmp/sing-box/cache.db'
	option log_level 'warn'
	option exclude_ntp '0'
	option shutdown_correctly '0'

config section 'main'
	option connection_type 'proxy'
	option proxy_config_type 'urltest'
	option enable_udp_over_tcp '0'
	list community_lists 'meta'
	list community_lists 'russia_inside'
	list community_lists 'telegram'
	list community_lists 'roblox'
	list community_lists 'discord'
	option user_domain_list_type 'disabled'
	option user_subnet_list_type 'disabled'
	list remote_domain_lists 'https://yarik88.github.io/ToporVPN/podkop.list'
	list remote_domain_lists 'https://iplist.opencck.org/?format=text&data=domains&site=kino.pub'
	list remote_domain_lists 'https://raw.githubusercontent.com/KharunDima/whatsapp-lists/main/results/domains.txt'
	list remote_subnet_lists 'https://yarik88.github.io/ToporVPN/podseti.list'
	list remote_subnet_lists 'https://iplist.opencck.org/?format=text&data=cidr4&site=kino.pub'
	list remote_subnet_lists 'https://raw.githubusercontent.com/KharunDima/whatsapp-lists/main/results/cidr_ipv4.txt'
	option mixed_proxy_enabled '0'
	option urltest_check_interval '5m'
	option urltest_tolerance '100'
	option urltest_testing_url 'https://www.gstatic.com/generate_204'

EOF

# VLESS-ссылки добавляем через uci — безопасно для ?, &, #, = и т.д.
echo ""
echo "Сейчас вставляй прокси-ссылки по одной (до 5 штук)."
echo "Подходят vless://, vmess://, trojan://, ss:// и т.п."
echo "Чтобы закончить раньше — введи любое слово без '://' (n / no / net / x / Enter)."
echo ""

added=0
i=1
LINKS_REPORT=""
while [ $i -le 5 ]; do
    printf "Ссылка #%d: " "$i"
    read -r link
    case "$link" in
        *://*)
            uci add_list podkop.main.urltest_proxy_links="$link"
            added=$((added + 1))
            LINKS_REPORT="${LINKS_REPORT}    ${added}. ${link}
"
            echo "  ✓ добавлена (#$added)"
            ;;
        *)
            echo "  → стоп"
            break
            ;;
    esac
    i=$((i + 1))
done

if [ $added -eq 0 ]; then
    echo "⚠ Ни одной ссылки не добавлено — podkop запустится без proxy-линков"
else
    echo "✓ Всего ссылок: $added"
fi

uci commit podkop
/etc/init.d/podkop enable 2>/dev/null
/etc/init.d/podkop restart
echo "✓ Podkop настроен и запущен"

# --- 7. WiFi ---
echo ""
echo "[7/8] Настройка WiFi (2.4 + 5 ГГц, одинаковый SSID/пароль)..."
for s in $(uci show wireless | grep "=wifi-iface" | cut -d= -f1); do
    uci set ${s}.ssid="$WIFI_SSID"
    uci set ${s}.encryption='psk2'
    uci set ${s}.key="$WIFI_PASS"
    uci set ${s}.disabled='0'
    uci set ${s}.mode='ap'
done
for r in $(uci show wireless | grep "=wifi-device" | cut -d= -f1); do
    uci set ${r}.disabled='0'
done
uci commit wireless
echo "✓ WiFi сконфигурирован: SSID=$WIFI_SSID / pass=$WIFI_PASS / WPA2-PSK (применится после перезагрузки)"

# --- 8. LAN IP + еженедельный ребут по cron ---
echo ""
echo "[8/8] LAN IP = $LAN_IP (применится после перезагрузки)..."
uci set network.lan.ipaddr="$LAN_IP"
uci set network.lan.netmask='255.255.255.0'
uci commit network

# Еженедельная перезагрузка — среда, 03:00 МСК
echo ""
echo "Настройка cron: автоматический ребут каждую среду в 03:00..."
CRON_FILE="/etc/crontabs/root"
touch "$CRON_FILE"
# убираем старые записи автоперезагрузки, чтобы не плодить дубли
sed -i '/# topor-weekly-reboot/d' "$CRON_FILE"
sed -i '/reboot/d' "$CRON_FILE"
echo "0 3 * * 3 /sbin/reboot # topor-weekly-reboot" >> "$CRON_FILE"
/etc/init.d/cron enable
/etc/init.d/cron restart
echo "✓ cron: ребут каждую среду 03:00"

# --- Финальный отчёт ---
echo ""
echo "Сбор информации о системе..."

SETUP_DATE=$(date "+%Y-%m-%d %H:%M:%S %Z")
MODEL=$(cat /tmp/sysinfo/model 2>/dev/null \
    || tr -d '\0' < /proc/device-tree/model 2>/dev/null \
    || echo "unknown")
BOARD_NAME=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "unknown")
. /etc/openwrt_release 2>/dev/null
OWRT_VERSION="${DISTRIB_DESCRIPTION:-unknown}"
OWRT_RELEASE="${DISTRIB_RELEASE:-unknown}"
OWRT_TARGET="${DISTRIB_TARGET:-unknown}"
OWRT_REVISION="${DISTRIB_REVISION:-unknown}"
KERNEL=$(uname -r)
ARCH=$(uname -m)
TOTAL_MEM=$(awk '/^MemTotal/{printf "%d MB", $2/1024}' /proc/meminfo 2>/dev/null || echo "?")
FREE_MEM=$(awk '/^MemAvailable/{printf "%d MB", $2/1024}' /proc/meminfo 2>/dev/null || echo "?")
UPTIME=$(awk '{printf "%d мин", $1/60}' /proc/uptime 2>/dev/null || echo "?")
WAN_MAC=$(cat /sys/class/net/eth0/address 2>/dev/null || echo "unknown")
PODKOP_VER=$(opkg list-installed podkop 2>/dev/null | awk '{print $3}')
FRPC_VER=$(opkg list-installed frpc 2>/dev/null | awk '{print $3}')

REPORT_FILE="/root/setup-info.txt"

# Формируем текст отчёта (один раз, в переменной)
REPORT="
=================================================
  ОТЧЁТ ПО НАСТРОЙКЕ РОУТЕРА
=================================================
Дата настройки:   $SETUP_DATE
Hostname:         $newname  (id=$rid)

--- Железо ---
Модель:           $MODEL
Board name:       $BOARD_NAME
Архитектура:      $ARCH
WAN MAC (eth0):   $WAN_MAC
Память:           $FREE_MEM свободно / $TOTAL_MEM всего
Uptime до ребута: $UPTIME

--- Прошивка ---
OpenWRT:          $OWRT_VERSION
Release:          $OWRT_RELEASE
Target:           $OWRT_TARGET
Revision:         $OWRT_REVISION
Kernel:           $KERNEL

--- Доступ ---
LAN IP:           $LAN_IP
SSH локально:     ssh root@$LAN_IP
SSH через frpc:   ssh root@router.toporrubit.ru -p $SSH_PORT
Web через frpc:   http://router.toporrubit.ru:$WEB_PORT
SFTP:             включён (openssh-sftp-server)
Пароль root:      88888888

--- WiFi ---
SSID 2.4 + 5 ГГц: $WIFI_SSID
Пароль:           $WIFI_PASS
Шифрование:       WPA2-PSK

--- frpc ---
Версия:           ${FRPC_VER:-?}
Сервер:           router.toporrubit.ru:63334 (TLS)
Туннель SSH:      $newname-ssh -> remote_port $SSH_PORT
Туннель Web:      $newname-web -> remote_port $WEB_PORT

--- Podkop ---
Версия:           ${PODKOP_VER:-?}
Режим:            urltest
DNS / Bootstrap:  77.88.8.8 / 8.8.8.8
Добавлено ссылок: $added
${LINKS_REPORT:-    (нет добавленных ссылок)}
--- Авто-обслуживание ---
Ребут по cron:    каждую среду в 03:00 (MSK)
Язык LuCI:        ru
=================================================
"

# Сохраняем в файл на роутере (доступен после ребута)
echo "$REPORT" > "$REPORT_FILE"
chmod 600 "$REPORT_FILE"

# Выводим в консоль
echo "$REPORT"
echo "📄 Отчёт сохранён в $REPORT_FILE — после ребута:  cat $REPORT_FILE"
echo ""
echo "============================================="
echo "  Настройка завершена."
echo "  Сохрани важные данные из сессии СЕЙЧАС —"
echo "  после reboot SSH отвалится, пока роутер"
echo "  не поднимется на новом LAN IP ($LAN_IP)."
echo "============================================="
echo ""

# Чистим буфер ввода перед финальным вопросом
while read -r -t 1 _ 2>/dev/null; do :; done

# y/n перед перезагрузкой
confirm=""
while true; do
    printf "Перезагрузить роутер сейчас? [y/N]: "
    read -r confirm
    case "$confirm" in
        y|Y|yes|YES|Yes|д|Д|да|ДА|Да)
            echo ""
            echo "✓ Перезагрузка через 3 секунды..."
            ( sleep 3 && reboot ) &
            exit 0
            ;;
        n|N|no|NO|No|н|Н|нет|НЕТ|Нет|"")
            echo ""
            echo "⏸  Ребут отложен. Запусти вручную, когда будешь готов:"
            echo "     reboot"
            echo ""
            echo "📄 Отчёт:  cat $REPORT_FILE"
            exit 0
            ;;
        *)
            echo "   Введи y (да) или n (нет)"
            ;;
    esac
done
