

import SwiftUI
import SwiftData
import UIKit

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
    @State private var editingCard: LoyaltyCard?

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
                        Label("Wallet Empty", systemImage: "creditcard")
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

                                HStack(spacing: 14) {

                                    Group {
                                        if let data = card.logoData,
                                           let uiImage = UIImage(data: data) {

                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()

                                        } else {

                                            Image(systemName: "creditcard.fill")
                                                .resizable()
                                                .scaledToFit()
                                                .padding(12)
                                                .foregroundStyle(.white.opacity(0.92))
                                        }
                                    }
                                    .frame(width: 56, height: 56)
                                    .background(
                                        RoundedRectangle(
                                            cornerRadius: 16,
                                            style: .continuous
                                        )
                                        .fill(
                                            Color(
                                                hex: card.colorHex ?? "#3B82F6") ?? .blue
                                        )
                                    )
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: 16,
                                            style: .continuous
                                        )
                                    )

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

                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {

                                Button {
                                    editingCard = card
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {

                                Button(role: .destructive) {

                                    if let index = cards.firstIndex(where: { $0.id == card.id }) {
                                        deleteCards(at: IndexSet(integer: index))
                                    }

                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
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
            .sheet(item: $editingCard) { card in
                EditLoyaltyCardView(card: card)
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
