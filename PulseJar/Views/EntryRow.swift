import SwiftUI

struct EntryRow: View {
    let entry: LedgerEntry
    /// When set, the amount is signed from this account's point of view.
    var perspective: Account?

    private var signed: Decimal {
        perspective.map { entry.signedAmount(for: $0) } ?? entry.signedAmount
    }

    /// Transfers shown without an account in mind have no direction, so no sign.
    private var showsSign: Bool {
        !(entry.kind == .transfer && perspective == nil)
    }

    private var amountColor: Color {
        if entry.status == .reversed {
            return .secondary
        }
        if entry.kind == .transfer, perspective == nil {
            return .secondary
        }
        return signed < 0 ? .primary : Theme.positive
    }

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: entry.iconName, tint: entry.tint, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .lineLimit(1)
                Text(entry.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                MoneyText(amount: showsSign ? signed : entry.amount, signed: showsSign)
                    .foregroundStyle(amountColor)
                    .strikethrough(entry.status == .reversed)
                if entry.status == .needsReview {
                    Text("Review")
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.accent)
                } else if entry.status == .reversed {
                    Text("Reversed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Opens an entry for review when it is waiting, otherwise for editing.
struct EntryLink: View {
    let entry: LedgerEntry
    var perspective: Account?

    var body: some View {
        NavigationLink {
            EntryEditView(mode: entry.status == .needsReview ? .review(entry) : .edit(entry))
        } label: {
            EntryRow(entry: entry, perspective: perspective)
        }
    }
}
