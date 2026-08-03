import SwiftUI
import SwiftData


struct WalletView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    @Query(
        sort: [
            SortDescriptor(\LoyaltyCard.sortOrder, order: .forward)
        ],
        animation: .smooth
    )
    private var cards: [LoyaltyCard]

    @State private var showAddCard = false
    @State private var editingCard: LoyaltyCard?
    @State private var searchText = ""
    @State private var pendingSortMode: String?
    @State private var showCustomSortInfo = false
    @State private var walletFilter = "all"

    @AppStorage("walletSortMode")
    private var walletSortMode: String = "alphabetical"

    private var ticketCount: Int {
        cards.filter { $0.itemType == "ticket" }.count
    }

    private var loyaltyCardCount: Int {
        cards.filter { $0.itemType != "ticket" }.count
    }

    private var filteredCards: [LoyaltyCard] {

        let source: [LoyaltyCard]

        if walletSortMode == "custom" {
            source = cards.sorted { $0.sortOrder < $1.sortOrder }
        } else {
            source = cards.sorted {
                let storeCompare = $0.storeName.localizedCaseInsensitiveCompare($1.storeName)

                if storeCompare == .orderedSame {
                    return ($0.cardHolder ?? "") < ($1.cardHolder ?? "")
                }

                return storeCompare == .orderedAscending
            }
        }

        let filteredByType: [LoyaltyCard]

        switch walletFilter {
        case "tickets":
            filteredByType = source.filter { $0.itemType == "ticket" }

        case "cards":
            filteredByType = source.filter { $0.itemType != "ticket" }

        default:
            filteredByType = source
        }

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return filteredByType
        }

        return filteredByType.filter {
            $0.storeName.localizedCaseInsensitiveContains(trimmed)
            || ($0.cardHolder?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {

        ZStack {

            AppGlassBackground()
            Color.clear
                .onAppear {

                    var needsSave = false


                    // Codice già esistente
                    if cards.allSatisfy({ $0.sortOrder == 0 }) && !cards.isEmpty {

                        let alphabetical = cards.sorted {
                            let storeCompare = $0.storeName.localizedCaseInsensitiveCompare($1.storeName)

                            if storeCompare == .orderedSame {
                                return ($0.cardHolder ?? "") < ($1.cardHolder ?? "")
                            }

                            return storeCompare == .orderedAscending
                        }

                        for (index, card) in alphabetical.enumerated() {
                            card.sortOrder = index + 1
                        }

                        needsSave = true
                    }

                    if needsSave {
                        try? modelContext.save()
                    }
                }

            NavigationStack {

            Group {

                if cards.isEmpty {

                    ContentUnavailableView {
                        Label("Wallet Empty", systemImage: "creditcard")
                    } description: {
                        Text("Store loyalty cards and tickets for quick access to QR codes and barcodes.")
                    } actions: {
                        Button("Add Item") {
                            showAddCard = true
                        }
                        .buttonStyle(.borderedProminent)
                    }

                } else {

                    List {
                        ForEach(filteredCards) { card in

                            let logoData = {

                                if let asset = card.logoAsset {

                                    return WalletAssetStore.loadData(
                                        relativePath: asset.relativePath
                                    )
                                }

                                // Compatibilità con le versioni precedenti
                                if let relativePath = card.loyaltyLogoRelativePath {

                                    return LoyaltyCardLogoStore.load(
                                        relativePath: relativePath
                                    )
                                }

                                return nil

                            }()

                            NavigationLink(value: card) {

                                HStack(spacing: 14) {

                                    Group {
                                        if let data = logoData,
                                           let uiImage = UIImage(data: data) {

                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()

                                        } else {

                                            Image(
                                                systemName: card.itemType == "ticket"
                                                ? "ticket.fill"
                                                : "creditcard"
                                            )
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
                                        .fill(Color.blue)
                                    )
                                    .overlay {
                                        RoundedRectangle(
                                            cornerRadius: 16,
                                            style: .continuous
                                        )
                                        .stroke(.white.opacity(0.15), lineWidth: 0.8)
                                    }
                                    .shadow(
                                        color: .black.opacity(colorScheme == .dark ? 0.25 : 0.12),
                                        radius: 8,
                                        y: 3
                                    )
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: 16,
                                            style: .continuous
                                        )
                                    )
                                    .overlay(alignment: .top) {
                                        Capsule()
                                            .fill(.white.opacity(0.08))
                                            .frame(width: 32, height: 1)
                                            .padding(.top, 2)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {

                                        Text(card.storeName)
                                            .font(.headline)

                                        Text(
                                            card.itemType == "ticket"
                                            ? "Ticket"
                                            : "Loyalty Card"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                        if let holder = card.cardHolder,
                                           !holder.isEmpty {


                                            Text(holder)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(

                                Color(.systemBackground)

                                    .opacity(colorScheme == .dark ? 0.3 : 0.26)

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

                                    deleteCard(card)

                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {

                                if sizeClass == .regular {

                                    Button {
                                        editingCard = card
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {

                                        deleteCard(card)

                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            .moveDisabled(
                                walletSortMode != "custom"
                                || walletFilter != "all"
                                || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                        }
                        .onMove { source, destination in
                            guard walletSortMode == "custom" else { return }
                            moveCards(from: source, to: destination)
                        }
                        .onDelete(perform: deleteCards)
                    }
                    .contentMargins(.bottom, 70, for: .scrollContent)
                    .contentMargins(.top, 10, for: .scrollContent)
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .searchable(
                        text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: Text("Search cards and tickets")
                    )
                }
            }
            .navigationDestination(for: LoyaltyCard.self) { card in
                LoyaltyCardDetailView(card: card)
                    .onAppear {
                        card.lastOpenedAt = Date()
                        try? modelContext.save()
                    }
            }
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .principal) {

                    VStack(spacing: 1) {

                        Text("Wallet")
                            .font(.headline)

                        Text(
                            "\(loyaltyCardCount) cards • \(ticketCount) tickets"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }

                ToolbarItem(placement: .topBarLeading) {

                    Picker("Filter", selection: $walletFilter) {
                        Label("All", systemImage: "square.on.square")
                            .tag("all")

                        Label("Cards", systemImage: "creditcard")
                            .tag("cards")

                        Label("Tickets", systemImage: "ticket")
                            .tag("tickets")
                    }
                    .pickerStyle(.menu)
                }

                ToolbarItem(placement: .topBarLeading) {

                    Picker(
                        "Order",
                        selection: Binding(
                            get: { walletSortMode },
                            set: { newValue in

                                guard newValue != walletSortMode else { return }

                                if newValue == "custom" {
                                    pendingSortMode = newValue
                                    showCustomSortInfo = true
                                } else {
                                    walletSortMode = newValue
                                }
                            }
                        )
                    ) {
                        Section(String(localized: "Sorting")) { }
                        Label("A-Z", systemImage: "textformat.abc")
                            .tag("alphabetical")

                        Label("Custom", systemImage: "line.3.horizontal")
                            .tag("custom")
                    }
                    .labelStyle(.iconOnly)
                    .pickerStyle(.menu)
                    .labelsHidden()
                }


                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddCard = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                            .padding(.trailing, 5)
                    }
                }
            }
            .sheet(isPresented: $showAddCard) {
                AddLoyaltyCardView()
            }
            .sheet(item: $editingCard) { card in
                EditLoyaltyCardView(card: card)
            }
            .confirmationDialog(
                "Custom Order",
                isPresented: $showCustomSortInfo,
                titleVisibility: .visible
            ) {

                Button("Enable Custom Order") {
                    walletSortMode = "custom"
                    pendingSortMode = nil
                }

                Button("Cancel", role: .cancel) {
                    pendingSortMode = nil
                }

            } message: {
                Text("Cards can always be reordered with drag and drop. Selecting A–Z restores alphabetical order.")
            }
        }
    }
    }

    private func moveCards(from source: IndexSet, to destination: Int) {

        guard walletSortMode == "custom" else { return }

        guard walletFilter == "all",
              searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        var reordered = cards.sorted {
            $0.sortOrder < $1.sortOrder
        }

        reordered.move(
            fromOffsets: source,
            toOffset: destination
        )

        for (index, card) in reordered.enumerated() {
            card.sortOrder = index + 1
        }

        try? modelContext.save()
    }
    
    
    private func deleteCard(_ card: LoyaltyCard) {

        deleteLoyaltyCard(
            card,
            in: modelContext
        )
    }
    

    // MARK: - Delete

    private func deleteCards(at offsets: IndexSet) {

        for index in offsets {

            guard filteredCards.indices.contains(index) else {
                continue
            }

            deleteLoyaltyCard(
                filteredCards[index],
                in: modelContext
            )
        }
    }
    
    private func isLightCardColor(_ hex: String?) -> Bool {

        guard let hex else {
            return false
        }

        let uiColor = UIColor(
            Color(hex: hex) ?? .blue
        )

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getRed(
            &red,
            green: &green,
            blue: &blue,
            alpha: &alpha
        ) else {
            return false
        }

        let brightness =
            ((red * 299) +
             (green * 587) +
             (blue * 114)) / 1000

        return brightness > 0.68
    }
    
    
}
