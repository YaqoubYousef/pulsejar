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

Every push to `main` (or **Actions → Build IPA → Run workflow**) runs the parser tests, builds an unsigned `PulseJar.ipa` with version `1.0.<run number>`, and publishes it as a GitHub Release (`build-<run number>`) together with a SideStore source file, `apps.json`.

Install and update through SideStore (the repository must be public so SideStore can download the release):

1. In SideStore, open **Sources → +** and add:
   `https://github.com/YaqoubYousef/pulsejar/releases/latest/download/apps.json`
2. Install PulseJar from that source. SideStore signs it with your free Apple ID.
3. After a new push, open SideStore and pull to refresh. The new build appears under **Updates**.
4. Refresh the app in SideStore at least every 7 days. Your data is kept across refreshes and updates.

Parser tests locally (needs Swift or Docker):

```bash
docker run --rm -v "$PWD/Packages/PulseJarCore:/pkg" -w /pkg swift:6.0 swift test
```

## Set up automatic recording

In the app: **Settings → Record messages automatically**.
