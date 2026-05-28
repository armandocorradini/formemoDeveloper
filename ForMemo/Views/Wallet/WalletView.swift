import SwiftUI
import SwiftData
import UIKit

struct WalletView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

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
    @State private var searchText = ""
    private var filteredCards: [LoyaltyCard] {

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return cards
        }

        return cards.filter {
            $0.storeName.localizedCaseInsensitiveContains(trimmed)
            || ($0.cardHolder?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

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
                        ForEach(filteredCards) { card in

                            let logoData = LoyaltyCardLogoStore.load(
                                relativePath: card.logoRelativePath
                            )

                            NavigationLink {
                                LoyaltyCardDetailView(card: card)
                            } label: {

                                HStack(spacing: 14) {

                                    Group {
                                        if let data = logoData,
                                           let uiImage = UIImage(data: data) {

                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()

                                        } else {

                                            Image(systemName: "creditcard.fill")
                                                .resizable()
                                                .scaledToFit()
                                                .padding(12)
                                                .foregroundStyle(
                                                    isLightCardColor(card.colorHex)
                                                    ? Color.black.opacity(0.82)
                                                    : Color.white.opacity(0.92)
                                                )
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
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(
                                        cornerRadius: 24,
                                        style: .continuous
                                    )
                                    .fill(
                                        colorScheme == .dark
                                        ? Color(red: 0.07, green: 0.08, blue: 0.13)
                                        : Color.white.opacity(0.72)
                                    )
                                    .overlay(
                                        RoundedRectangle(
                                            cornerRadius: 24,
                                            style: .continuous
                                        )
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(colorScheme == .dark ? 0.10 : 0.28),
                                                    Color.clear
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(
                                            cornerRadius: 24,
                                            style: .continuous
                                        )
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(colorScheme == .dark ? 0.14 : 0.22),
                                                    Color.white.opacity(colorScheme == .dark ? 0.015 : 0.05),
                                                    Color.clear
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(
                                            cornerRadius: 24,
                                            style: .continuous
                                        )
                                        .stroke(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(colorScheme == .dark ? 0.18 : 0.26),
                                                    Color.white.opacity(colorScheme == .dark ? 0.025 : 0.06),
                                                    Color.clear
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.05
                                        )
                                    )
                                    .shadow(
                                        color: .black.opacity(colorScheme == .dark ? 0.52 : 0.12),
                                        radius: 22,
                                        y: 10
                                    )
                                )
                                .padding(.vertical, 1)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(
                                EdgeInsets(
                                    top: -2,
                                    leading: 18,
                                    bottom: 6,
                                    trailing: 18
                                )
                            )
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
                    .contentMargins(.bottom, 70, for: .scrollContent)
                    .contentMargins(.top, 10, for: .scrollContent)
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .searchable(
                        text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: Text("Search cards")
                    )
                }
            }
            .navigationTitle("Wallet")
            .toolbar {

                ToolbarItem(placement: .principal) {

                    VStack(spacing: 1) {

                        Text("Wallet")
                            .font(.headline)

                        Text("\(cards.count) cards")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

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
    
    private func isLightCardColor(_ hex: String?) -> Bool {

        guard
            let hex,
            let uiColor = UIColor(
                Color(hex: hex) ?? .blue
            ).cgColor.components
        else {
            return false
        }

        let red = uiColor[0]
        let green = uiColor[1]
        let blue = uiColor[2]

        let brightness =
            ((red * 299) +
             (green * 587) +
             (blue * 114)) / 1000

        return brightness > 0.68
    }
    
    
}

#Preview {
    WalletView()
}
