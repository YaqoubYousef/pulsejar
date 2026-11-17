# PulseJar

A personal iPhone finance app. All data stays on the phone (SwiftData), with no server.

- Accounts (bank, cash, e-wallet, savings, card) with balances checked against the bank's reported balance
- Expense and income categories, with remembered merchant categories
- Debts: lend, borrow and repayments per person
- Bank SMS read through a Shortcuts automation. Purchases and salary are recorded directly, CliQ transfers wait for review, reversals cancel the original payment, and internal transfers are merged into one entry
- JSON backup and restore through the Files app

## Layout

- `Packages/PulseJarCore`: bank message parser (pure Swift, tested on Linux too)
- `PulseJar`: the SwiftUI app (models, ingest logic, screens, Shortcuts action)
- `project.yml`: XcodeGen spec; the `.xcodeproj` is generated, not committed
- `.github/workflows/build.yml`: runs the parser tests, then builds an unsigned `PulseJar.ipa`

## Build (no Mac needed)

1. Push this folder to a GitHub repository, private or public.
2. Open **Actions → Build IPA → Run workflow**. When it finishes, download the **PulseJar-ipa** artifact and unzip it to get `PulseJar.ipa`.
3. Install it on the iPhone with SideStore, which signs it with your free Apple ID. Refresh it in SideStore at least every 7 days. Your data is kept across refreshes.

Parser tests locally (needs Swift or Docker):

```bash
docker run --rm -v "$PWD/Packages/PulseJarCore:/pkg" -w /pkg swift:6.0 swift test
```

## Set up automatic recording

In the app: **Settings → Record messages automatically**.
