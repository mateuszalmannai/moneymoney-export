#!/bin/bash
# moneymoney-export: export all MoneyMoney accounts and transactions as
# property lists, with one command.
#
#   moneymoney-export.sh [-o DIR] [-s YYYY-MM-DD]
#
# MoneyMoney must be open and unlocked. The script only reads from MoneyMoney.
# See README.md.

set -u

usage() {
    cat <<'EOF'
usage: moneymoney-export.sh [-o DIR] [-s YYYY-MM-DD]

  -o DIR         output folder. Default: $MONEYMONEY_EXPORT_DIR, else
                 ~/Library/Mobile Documents/com~apple~CloudDocs/moneymoney-export
  -s YYYY-MM-DD  export transactions from this date on. Default: all of them
                 (asked for as "from 2000-01-01").
  -h             show this help

Writes accounts.plist and transactions.plist into the output folder.
Exit codes: 0 ok, 1 usage, 2 MoneyMoney not running, 3 export failed.
EOF
}

out="${MONEYMONEY_EXPORT_DIR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/moneymoney-export}"
since=""

while getopts ":o:s:h" opt; do
    case "$opt" in
        o) out="$OPTARG" ;;
        s) since="$OPTARG" ;;
        h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

if [ $# -gt 0 ]; then
    usage >&2
    exit 1
fi

# The round trip through date(1) rejects dates that have the right shape but
# do not exist (2026-13-45, 2026-02-30).
if [ -n "$since" ]; then
    if ! [[ "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] ||
        [ "$(date -j -f "%Y-%m-%d" "$since" "+%Y-%m-%d" 2> /dev/null)" != "$since" ]; then
        echo "moneymoney-export: start date must be a real date like 2026-09-01, got '$since'" >&2
        exit 1
    fi
fi

# Checked with pgrep, not AppleScript: `tell application` would launch
# MoneyMoney if it were closed.
if ! pgrep -x MoneyMoney > /dev/null; then
    echo "moneymoney-export: MoneyMoney is not running. Open and unlock it, then run this again." >&2
    exit 2
fi

fail() { # fail <message>: MoneyMoney did not deliver; nothing has been replaced yet
    echo "moneymoney-export: $1" >&2
    echo "Nothing was written; a previous export is unchanged. Is MoneyMoney unlocked?" >&2
    exit 3
}

die() { # die <message>: a problem with the output folder, not with MoneyMoney
    echo "moneymoney-export: $1" >&2
    exit 3
}

mkdir -p "$out" 2> /dev/null || die "cannot create output folder: $out"

# Both exports go to temporary files in the output folder and are renamed into
# place only when both are valid, so a failed run never leaves half an export.
tmp_accounts="$out/.accounts.plist.$$.tmp"
tmp_transactions="$out/.transactions.plist.$$.tmp"
trap 'rm -f "$tmp_accounts" "$tmp_transactions"' EXIT

fetch() { # fetch <label> <applescript> <file>
    local label="$1" applescript="$2" file="$3" message
    if ! message="$(osascript -e "$applescript" 2>&1 > "$file")"; then
        fail "$label export failed: $message"
    fi
    # plutil alone is not enough: it also accepts old-style property lists,
    # and a bare word or a file path is one of those.
    if [ "$(head -c 5 "$file")" != "<?xml" ] || ! plutil -lint "$file" > /dev/null 2>&1; then
        fail "$label export did not return a property list"
    fi
}

# MoneyMoney refuses `export transactions` without a start date ("Some
# parameter is missing"), so the full history is asked for from a date before
# any account can have data.
from=" from date \"${since:-2000-01-01}\""

fetch "accounts" 'tell application "MoneyMoney" to export accounts' "$tmp_accounts"
fetch "transactions" "tell application \"MoneyMoney\" to export transactions$from as \"plist\"" "$tmp_transactions"

mv -f "$tmp_accounts" "$out/accounts.plist" ||
    die "cannot write $out/accounts.plist; a previous export is unchanged"
mv -f "$tmp_transactions" "$out/transactions.plist" ||
    die "cannot write $out/transactions.plist. The export is incomplete: accounts.plist is new, transactions.plist is not. Run the export again."

# Summary, from a text scan of the XML.
accounts="$(grep -c '<key>uuid</key>' "$out/accounts.plist")"
transactions="$(grep -c '<key>bookingDate</key>' "$out/transactions.plist")"
range="$(awk '
    /<key>bookingDate<\/key>/ {
        if ($0 !~ /<date>/) getline
        if (match($0, /<date>[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/))
            print substr($0, RSTART + 6, 10)
    }' "$out/transactions.plist" | sort | awk 'NR == 1 { first = $0 } { last = $0 } END { if (NR) print first " .. " last }')"

echo "Wrote $out"
echo "  accounts.plist      $accounts account entries"
echo "  transactions.plist  $transactions transactions${range:+, $range}"
