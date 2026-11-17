import SwiftUI

struct EntryRow: View {
    let entry: LedgerEntry
    /// When set, the amount is signed from this account's point of view.
    var perspective: Account?

    private var signed: Decimal {
        perspective.map { entry.signedAmount(for: $0) } ?? entry.signedAmount
    }

    private var amountText: String {
        if entry.kind == .transfer, perspective == nil {
            return entry.amount.money()
        }
        return signed.signedMoney()
    }

    private var amountColor: Color {
        if entry.status == .reversed {
            return .secondary
        }
        if entry.kind == .transfer, perspective == nil {
            return .primary
        }
        return signed < 0 ? .primary : .green
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.iconName)
                .font(.callout)
                .foregroundStyle(entry.tint)
                .frame(width: 34, height: 34)
                .background(entry.tint.opacity(0.15), in: Circle())

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
                Text(amountText)
                    .monospacedDigit()
                    .foregroundStyle(amountColor)
                    .strikethrough(entry.status == .reversed)
                if entry.status == .needsReview {
                    Text("Review")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                } else if entry.status == .reversed {
                    Text("Reversed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
