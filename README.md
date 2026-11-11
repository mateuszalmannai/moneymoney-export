# moneymoney-export

Exports every account and every transaction from [MoneyMoney](https://moneymoney.app)
as two property-list files, with one command. It replaces opening each account and
exporting it by hand.

The script only reads from MoneyMoney. It needs no account numbers or other settings.

## Requirements

- macOS with MoneyMoney installed
- MoneyMoney is open and unlocked when the script runs. The script does not start
  MoneyMoney.

## Usage

```bash
./moneymoney-export.sh                  # everything, into the default folder
./moneymoney-export.sh -s 2026-09-01    # only transactions from this date on
./moneymoney-export.sh -o ~/some/folder # another output folder
```

The output folder is, in this order: `-o DIR`, the environment variable
`MONEYMONEY_EXPORT_DIR`, or
`~/Library/Mobile Documents/com~apple~CloudDocs/moneymoney-export` (a folder in iCloud
Drive, so the export reaches your other Macs by itself). The folder is created if it
does not exist.

On success the script prints what it wrote:

```
Wrote /path/to/moneymoney-export
  accounts.plist      10 account entries
  transactions.plist  4321 transactions, 2018-03-01 .. 2026-11-11
```

## Output

| File | Content |
|------|---------|
| `accounts.plist` | MoneyMoney's `export accounts`: one entry per account and per account group, with name, account number, UUID, currency, balance and the time of the last refresh. |
| `transactions.plist` | MoneyMoney's `export transactions as "plist"`: the transactions of all accounts. Each one names its account in `accountUuid`. |

Both files are written under a temporary name and renamed into place only when both
exports succeeded, so a sync service never picks up half an export. If a run fails, the
files of the previous run stay as they were.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Both files written |
| 1 | Wrong usage (unknown option, malformed date) |
| 2 | MoneyMoney is not running |
| 3 | The export failed, for example because MoneyMoney is locked. MoneyMoney's own message is printed. |

## Tests

```bash
bash tests/run.sh
```

The tests replace `osascript` and `pgrep` with stubs and use made-up data, so they run
on any Mac, with or without MoneyMoney.

## License

MIT, see [LICENSE](LICENSE).
