#!/bin/bash
# Tests for moneymoney-export.sh. No MoneyMoney needed: `osascript` and `pgrep`
# are replaced by stubs on PATH, and all data is synthetic.
#
#   bash tests/run.sh

set -u

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../moneymoney-export.sh"
pass=0
fail=0

# --- fixtures ---------------------------------------------------------------

make_stubs() { # make_stubs <tmp dir>
    local tmp="$1"
    mkdir -p "$tmp/bin" "$tmp/data" "$tmp/home"

    cat > "$tmp/data/accounts.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
	<dict>
		<key>group</key>
		<true/>
		<key>name</key>
		<string>All accounts</string>
		<key>uuid</key>
		<string>00000000-0000-0000-0000-000000000001</string>
	</dict>
	<dict>
		<key>group</key>
		<false/>
		<key>name</key>
		<string>Test Giro</string>
		<key>uuid</key>
		<string>00000000-0000-0000-0000-000000000002</string>
	</dict>
</array>
</plist>
EOF

    cat > "$tmp/data/transactions.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>creator</key>
	<string>Stub</string>
	<key>transactions</key>
	<array>
		<dict>
			<key>amount</key>
			<real>-1.5</real>
			<key>bookingDate</key>
			<date>2026-10-13T12:00:00Z</date>
			<key>name</key>
			<string>Example Shop</string>
		</dict>
		<dict>
			<key>amount</key>
			<real>10</real>
			<key>bookingDate</key>
			<date>2018-03-01T12:00:00Z</date>
			<key>name</key>
			<string>Example Employer</string>
		</dict>
		<dict>
			<key>amount</key>
			<real>-3</real>
			<key>bookingDate</key>
			<date>2026-11-11T12:00:00Z</date>
			<key>name</key>
			<string>Example Bakery</string>
		</dict>
	</array>
</dict>
</plist>
EOF

    cat > "$tmp/bin/pgrep" <<'EOF'
#!/bin/bash
exit "${STUB_PGREP_RC:-0}"
EOF

    cat > "$tmp/bin/osascript" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$STUB_LOG"
if [ "${STUB_MODE:-valid}" = "fail" ]; then
    echo "execution error: MoneyMoney got an error: Locked database. (-2720)" >&2
    exit 1
fi
case "$*" in
    *"export accounts"*)
        cat "$STUB_DATA/accounts.plist" ;;
    *"export transactions"*)
        [ "${STUB_MODE:-valid}" = "empty_tx" ] && exit 0
        cat "$STUB_DATA/transactions.plist" ;;
esac
EOF
    chmod +x "$tmp/bin/pgrep" "$tmp/bin/osascript"
}

# run_script <args...>: runs the script with the stubs; sets $rc, writes
# $tmp/stdout and $tmp/stderr. HOME points into the temp dir so that no test
# can ever touch the real default output folder.
run_script() {
    PATH="$tmp/bin:$PATH" HOME="$tmp/home" \
        STUB_LOG="$tmp/osascript.log" STUB_DATA="$tmp/data" \
        bash "$script" "$@" > "$tmp/stdout" 2> "$tmp/stderr"
    rc=$?
}

seed_previous_export() {
    mkdir -p "$tmp/out"
    echo "OLD ACCOUNTS" > "$tmp/out/accounts.plist"
    echo "OLD TRANSACTIONS" > "$tmp/out/transactions.plist"
}

# --- assertions -------------------------------------------------------------

check() { # check <description> <command...>
    local desc="$1"
    shift
    if ! "$@"; then
        echo "    assertion failed: $desc"
        failed=1
    fi
}

rc_is() { [ "$rc" -eq "$1" ]; }
file_contains() { grep -qF -- "$2" "$1" 2>/dev/null; }
file_lacks() { ! grep -qF -- "$2" "$1" 2>/dev/null; }
is_plist() { plutil -lint "$1" > /dev/null 2>&1; }
no_temp_files() { [ -z "$(find "$1" -name '*.tmp*' 2>/dev/null)" ]; }
previous_export_untouched() {
    [ "$(cat "$tmp/out/accounts.plist")" = "OLD ACCOUNTS" ] &&
        [ "$(cat "$tmp/out/transactions.plist")" = "OLD TRANSACTIONS" ]
}
osascript_not_called() { [ ! -e "$tmp/osascript.log" ]; }

# --- tests ------------------------------------------------------------------

test_writes_both_files() {
    run_script -o "$tmp/out"
    check "exit 0 (got $rc)" rc_is 0
    check "accounts.plist is a property list" is_plist "$tmp/out/accounts.plist"
    check "transactions.plist is a property list" is_plist "$tmp/out/transactions.plist"
    check "no temp files left" no_temp_files "$tmp/out"
}

test_prints_summary() {
    run_script -o "$tmp/out"
    check "account count" file_contains "$tmp/stdout" "2 account entries"
    check "transaction count" file_contains "$tmp/stdout" "3 transactions"
    check "date range" file_contains "$tmp/stdout" "2018-03-01 .. 2026-11-11"
    check "output path" file_contains "$tmp/stdout" "$tmp/out"
}

test_no_date_by_default() {
    run_script -o "$tmp/out"
    check "asks for plist" file_contains "$tmp/osascript.log" 'export transactions as "plist"'
    check "no from date" file_lacks "$tmp/osascript.log" "from date"
}

test_passes_start_date() {
    run_script -o "$tmp/out" -s 2026-09-01
    check "exit 0 (got $rc)" rc_is 0
    check "from date passed" file_contains "$tmp/osascript.log" 'from date "2026-09-01"'
}

test_rejects_bad_date() {
    run_script -o "$tmp/out" -s 01.09.2026
    check "exit 1 (got $rc)" rc_is 1
    check "osascript never called" osascript_not_called
}

test_not_running() {
    seed_previous_export
    STUB_PGREP_RC=1 run_script -o "$tmp/out"
    check "exit 2 (got $rc)" rc_is 2
    check "osascript never called" osascript_not_called
    check "previous export untouched" previous_export_untouched
}

test_osascript_fails() {
    seed_previous_export
    STUB_MODE=fail run_script -o "$tmp/out"
    check "exit 3 (got $rc)" rc_is 3
    check "passes on MoneyMoney's message" file_contains "$tmp/stderr" "Locked database."
    check "previous export untouched" previous_export_untouched
    check "no temp files left" no_temp_files "$tmp/out"
}

test_invalid_plist() {
    seed_previous_export
    STUB_MODE=empty_tx run_script -o "$tmp/out"
    check "exit 3 (got $rc)" rc_is 3
    check "previous export untouched" previous_export_untouched
    check "no temp files left" no_temp_files "$tmp/out"
}

test_creates_output_dir() {
    run_script -o "$tmp/new/nested/out"
    check "exit 0 (got $rc)" rc_is 0
    check "file in created dir" is_plist "$tmp/new/nested/out/accounts.plist"
}

test_env_var_dir() {
    MONEYMONEY_EXPORT_DIR="$tmp/envout" run_script
    check "exit 0 (got $rc)" rc_is 0
    check "accounts in env dir" is_plist "$tmp/envout/accounts.plist"
    check "transactions in env dir" is_plist "$tmp/envout/transactions.plist"
}

# --- runner -----------------------------------------------------------------

unset MONEYMONEY_EXPORT_DIR STUB_MODE STUB_PGREP_RC

for t in writes_both_files prints_summary no_date_by_default passes_start_date \
    rejects_bad_date not_running osascript_fails invalid_plist \
    creates_output_dir env_var_dir; do
    tmp="$(mktemp -d)"
    make_stubs "$tmp"
    failed=0
    rc=-1
    "test_$t"
    if [ "$failed" -eq 0 ]; then
        echo "ok    $t"
        pass=$((pass + 1))
    else
        echo "FAIL  $t"
        fail=$((fail + 1))
    fi
    rm -rf "$tmp"
done

echo
echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
