#!/usr/bin/env bash

# Switch a Glimmer deployment between the legacy imageserver and another image
# server, by choosing which "SetEnv IMAGESERVER_URL" line is active in its Apache
# vhost. The vhost holds one line per server; all but one are commented out, e.g.
#
#   SetEnv IMAGESERVER_URL "https://images.example.org/pahma/imageserver"
#   #SetEnv IMAGESERVER_URL "https://webapps.cspace.berkeley.edu/pahma/imageserver"
#
# The legacy line is the one with webapps.cspace.berkeley.edu; "new" is the other.
# Run as a user with sudo (e.g. ssm-user). Rails reads IMAGESERVER_URL at boot, so
# a switch reloads Apache and restarts the app (after asking).

set -euo pipefail

LEGACY_HOST="webapps.cspace.berkeley.edu"
SUDO=${SUDO-sudo}

function usage() {
    echo
    echo "    Usage: $0 [-c vhost.conf] [-m museum] [-n] status|legacy|new"
    echo
    echo "    status   show the IMAGESERVER_URL lines and the running app's value"
    echo "    legacy   make the ${LEGACY_HOST} line active"
    echo "    new      make the other line active"
    echo
    echo "    -c  Apache vhost (default /etc/apache2/sites-available/portal-qa.conf)"
    echo "    -m  museum, for the app at ~app_cspace/projects/search_<museum> (default pahma)"
    echo "    -n  preview: show the change, change nothing"
    echo
    echo "    e.g.   $0 -n legacy"
    echo
    exit 1
}

CONF=/etc/apache2/sites-available/portal-qa.conf
MUSEUM=pahma
PREVIEW=false
while getopts "c:m:nh" opt; do
    case $opt in
        c) CONF=$OPTARG ;;
        m) MUSEUM=$OPTARG ;;
        n) PREVIEW=true ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] || usage
ACTION=$1
case $ACTION in status|legacy|new) ;; *) usage ;; esac

APP_DIR=${APP_DIR:-/home/app_cspace/projects/search_${MUSEUM}}
LINE_RE='^[[:space:]]*#?[[:space:]]*SetEnv[[:space:]]+IMAGESERVER_URL[[:space:]]'

[ -r "$CONF" ] || { echo "can't read $CONF" ; exit 1 ; }

function app_value() {
    local pid
    pid=$(pgrep -f "RubyApp: ${APP_DIR}" | head -1 || true)
    if [ -z "$pid" ]; then
        echo "app not running (load a page to start it)"
        return
    fi
    echo "app pid ${pid}: $($SUDO cat /proc/${pid}/environ | tr '\0' '\n' | grep '^IMAGESERVER_URL=' || echo 'IMAGESERVER_URL not set')"
}

echo "IMAGESERVER_URL lines in ${CONF}:"
grep -nE "$LINE_RE" "$CONF" || echo "   (none)"
echo "$(app_value)"
[ "$ACTION" == "status" ] && exit 0

# exactly one legacy line and one new line, so the choice is never ambiguous
legacy_count=$(grep -E "$LINE_RE" "$CONF" | grep -c "$LEGACY_HOST" || true)
new_count=$(grep -E "$LINE_RE" "$CONF" | grep -vc "$LEGACY_HOST" || true)
if [ "$legacy_count" -ne 1 ] || [ "$new_count" -ne 1 ]; then
    echo "expected one legacy and one new IMAGESERVER_URL line; found ${legacy_count} and ${new_count}. fix ${CONF} by hand."
    exit 1
fi

# comment out every IMAGESERVER_URL line, then uncomment the chosen one, keeping indentation
NEW_CONF=$(mktemp)
trap 'rm -f "$NEW_CONF"' EXIT
awk -v re="$LINE_RE" -v host="$LEGACY_HOST" -v want="$ACTION" '
    $0 ~ re {
        match($0, /^[[:space:]]*/); indent = substr($0, 1, RLENGTH)
        body = substr($0, RLENGTH + 1); sub(/^#[[:space:]]*/, "", body)
        is_legacy = index(body, host) > 0
        active = (want == "legacy") ? is_legacy : !is_legacy
        print indent (active ? "" : "#") body
        next
    }
    { print }
' "$CONF" > "$NEW_CONF"

if cmp -s "$CONF" "$NEW_CONF"; then
    echo "already ${ACTION}: nothing to do"
    exit 0
fi

echo
diff -u "$CONF" "$NEW_CONF" || true
if $PREVIEW; then
    echo
    echo "preview only: nothing changed"
    exit 0
fi

BACKUP="${CONF}.bak-$(date +%Y%m%d%H%M%S)"
$SUDO cp -p "$CONF" "$BACKUP"
$SUDO cp "$NEW_CONF" "$CONF"
echo
echo "saved ${CONF} (backup ${BACKUP})"
if ! $SUDO apache2ctl configtest; then
    $SUDO cp -p "$BACKUP" "$CONF"
    echo "configtest failed: restored ${CONF} from the backup"
    exit 1
fi

echo
read -r -p "Reload Apache and restart the ${MUSEUM} app now? [y/N] " answer
if [[ ! "$answer" =~ ^[Yy] ]]; then
    $SUDO cp -p "$BACKUP" "$CONF"
    echo "not applied: restored ${CONF} from the backup"
    exit 0
fi

$SUDO systemctl reload apache2
$SUDO -u app_cspace touch "${APP_DIR}/tmp/restart.txt"
echo "Apache reloaded and ${MUSEUM} app restart requested."
echo "Load any ${MUSEUM} page, then check with: $0 -c ${CONF} -m ${MUSEUM} status"
