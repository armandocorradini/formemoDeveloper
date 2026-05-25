

import SwiftUI
import SwiftData

struct WalletView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(
        sort: [
            SortDescriptor(\LoyaltyCard.storeName, order: .forward),
            SortDescriptor(\LoyaltyCard.cardHolder, order: .forward)
        ],
        animation: .smooth
    )
    private var cards: [LoyaltyCard]

    @State private var showAddCard = false

    var body: some View {

        ZStack {

            LinearGradient(
                colors: [backColor1, backColor2],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            Color.clear
                .onAppear {
                    UITableView.appearance().backgroundColor = .clear
                    UITableViewCell.appearance().backgroundColor = .clear
                    UITableViewHeaderFooterView.appearance().tintColor = .clear
                    UITableViewHeaderFooterView.appearance().backgroundView = UIView(frame: .zero)
                }

            NavigationStack {

            Group {

                if cards.isEmpty {

                    ContentUnavailableView {
                        Label("Wallet Empty", systemImage: "wallet.pass")
                    } description: {
                        Text("Add your loyalty cards to quickly access barcodes.")
                    } actions: {
                        Button("Add Card") {
                            showAddCard = true
                        }
                        .buttonStyle(.borderedProminent)
                    }

                } else {

                    List {

                        ForEach(cards) { card in

                            NavigationLink {
                                LoyaltyCardDetailView(card: card)
                            } label: {

                                VStack(alignment: .leading, spacing: 4) {

                                    Text(card.storeName)
                                        .font(.headline)

                                    if let holder = card.cardHolder,
                                       !holder.isEmpty {

                                        Text(holder)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .onDelete(perform: deleteCards)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
            }
            .navigationTitle("Wallet")
            .containerBackground(.clear, for: .navigation)
            .toolbar {

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddCard = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddCard) {
                AddLoyaltyCardView()
            }
        }
    }
    }

    // MARK: - Delete

    private func deleteCards(at offsets: IndexSet) {

        for index in offsets {
            modelContext.delete(cards[index])
        }

        try? modelContext.save()
    }
}

#Preview {
    WalletView()
}
