import SwiftUI

// MARK: - Posizione condivisa delle row

enum TaskRowPosition {
    case single
    case first
    case middle
    case last
}

// MARK: - Metriche condivise

enum TaskRowMetrics {

    // Altezza base condivisa tra List e Weekly.
    // Aumentando questo valore tutte le card diventano più alte globalmente.
    static let rowHeight: CGFloat = 85

    // Raggio degli angoli utilizzato dalle card grouped.
    // Controlla quanto risultano morbide le sezioni grouped.
    static let groupedCornerRadius: CGFloat = 22

    // Corner radius utilizzato dalle row plain.
    static let plainCornerRadius: CGFloat = 0

    // Corner radius minimo usato per evitare artefatti
    // nelle row centrali grouped.
    static let groupedMiddleCornerRadius: CGFloat = 0.5
    

    // Padding interno sinistro per le row plain.
    static let plainLeadingPadding: CGFloat = 12
    // Padding interno destro per le row plain.
    static let plainTrailingPadding: CGFloat = 12

    // Padding interno sinistro per le row grouped.
    static let groupedLeadingPadding: CGFloat = 12
    // Padding interno destro per le row grouped.
    static let groupedTrailingPadding: CGFloat = 0

    // Margine sinistro dei separator.
    // Mantiene il separator allineato al contenuto.
    static let separatorLeadingInset: CGFloat = 72
    // Margine destro dei separator.
    static let separatorTrailingInset: CGFloat = 12

    // Spessore dei separator personalizzati.
    // Valori piccoli riducono il rumore visivo.
    static let separatorHeight: CGFloat = 0.35

    // Raggio blur utilizzato dalle ombre delle row.
    // Valori più alti creano ombre più morbide.
    static let shadowRadius: CGFloat = 8
    // Offset verticale delle ombre.
    static let shadowYOffset: CGFloat = 3

    // Larghezza della barra verticale di highlight/priorità.
    static let highlightBarWidth: CGFloat = 1.5
    // Altezza della barra verticale di highlight/priorità.
    static let highlightBarHeight: CGFloat = 38

    // Padding verticale utilizzato nella Weekly.
    // Controlla la densità visiva delle row grouped.
    static let weeklyVerticalPadding: CGFloat = 14
    // Padding orizzontale utilizzato nella Weekly.
    static let weeklyHorizontalPadding: CGFloat = 16

    // Larghezza condivisa della colonna data/giorno.
    static let dateColumnWidth: CGFloat = 44

    // MARK: - Legacy compat

    // TODO: rimuovere dopo migrazione completa dei layout.
    // Usare TaskRowLayout.* per tutta la geometria orizzontale.
    // Padding destro standard del contenuto row.
    static let rowTrailingContentPadding: CGFloat = 10

    // Padding destro utilizzato dallo style0.
    static let style0TrailingContentPadding: CGFloat = 14

//     spazio tra barra highlight e colonna data in weekly
    static let groupedContentLeadingInset: CGFloat = groupedLeadingPadding

    // Restituisce il padding sinistro corretto
    // in base allo stile plain/grouped.
    static func leadingPadding(
        for style: TaskListStyle
    ) -> CGFloat {

        style == .plain
        ? plainLeadingPadding
        : groupedLeadingPadding
    }

    // Restituisce il padding destro corretto
    // in base allo stile plain/grouped.
    static func trailingPadding(
        for style: TaskListStyle
    ) -> CGFloat {

        style == .plain
        ? plainTrailingPadding
        : groupedTrailingPadding
    }

    // Controlla gli spazi esterni attorno alle row.
    // IMPORTANTE:
    // - top controlla lo spazio tra gruppi/giorni
    // - bottom controlla lo spazio sotto i gruppi
    // - leading/trailing controllano il respiro orizzontale
    static func insets(
        for style: TaskListStyle,
        position: TaskRowPosition
    ) -> EdgeInsets {

        switch style {

        case .plain:

            // Spaziatura della lista plain.
            return EdgeInsets(
                top: 0,
                leading: 0,
                bottom: 0,
                trailing: 0
            )

        // Le row grouped NON gestiscono più
        // la distanza tra giornate.
        // La separazione reale tra gruppi viene
        // gestita esternamente dalla ListView.
        case .grouped:

            return EdgeInsets(
                top: position == .first || position == .single ? 6 : 0,
                leading: groupedLeadingPadding,
                bottom: position == .last || position == .single ? 6 : 0,
                trailing: groupedLeadingPadding
            )
        }
    }
}

// MARK: - Tema condiviso

enum TaskRowTheme {

    // Raggio angoli della barra verticale di highlight/priorità.
    // Valori bassi rendono la barra più netta.
    static let highlightCornerRadius: CGFloat = 2

    // Distanza della barra highlight dal bordo sinistro della row.
    static let highlightLeadingPadding: CGFloat = 8

    // Opacità dei separator in dark mode.
    // Valori bassi riducono il rumore visivo.
    static let separatorOpacityDark: Double = 0.39

    // Opacità dei separator in light mode.
    static let separatorOpacityLight: Double = 0.26

    // Intensità ombre in dark mode.
    // Valori alti aumentano la percezione di profondità.
    static let shadowOpacityDark: Double = 0.16

    // Intensità ombre in light mode.
    static let shadowOpacityLight: Double = 0.08

    // Intensità background delle task Today in dark mode.
    static let todayBackgroundOpacityDark: Double = 0.50

    // Intensità background delle task Today in light mode.
    static let todayBackgroundOpacityLight: Double = 0.72

    // Opacità standard delle row in dark mode.
    static let regularBackgroundOpacityDark: Double = 0.22

    // Opacità standard delle row in light mode.
    static let regularBackgroundOpacityLight: Double = 0.26

    // Fill principale utilizzato da tutte le card.
    // Si adatta automaticamente a today/non-today e dark/light mode.
    static func cardFill(
        isToday: Bool,
        colorScheme: ColorScheme
    ) -> Color {

        Color(.systemBackground).opacity(
            isToday
            ? (
                colorScheme == .dark
                ? todayBackgroundOpacityDark
                : todayBackgroundOpacityLight
            )
            : (
                colorScheme == .dark
                ? regularBackgroundOpacityDark
                : regularBackgroundOpacityLight
            )
        )
    }

    // Layer secondario utilizzato dietro le card grouped
    // per creare maggiore profondità.
    static func groupedBackgroundLayer(
        colorScheme: ColorScheme
    ) -> Color {

        Color.white.opacity(
            colorScheme == .dark
            ? 0.02
            : 0.04
        )
    }

    // Builder condiviso per il colore dei separator.
    static func separator(
        colorScheme: ColorScheme
    ) -> Color {

        colorScheme == .dark
        ? Color.white.opacity(separatorOpacityDark)
        : Color.black.opacity(separatorOpacityLight)
    }

    // Builder condiviso per il colore delle ombre.
    static func shadow(
        colorScheme: ColorScheme
    ) -> Color {

        Color.black.opacity(
            colorScheme == .dark
            ? shadowOpacityDark
            : shadowOpacityLight
        )
    }
}

// MARK: - Rendering metrics condivise

enum TaskRowRendering {

    // Intensità shadow layer dark mode.
    static let shadowOpacityDark: CGFloat = 0.72

    // Intensità shadow layer light mode.
    static let shadowOpacityLight: CGFloat = 0.42

    // Moltiplicatore blur della shadow.
    static let shadowBlurFactor: CGFloat = 0.45

    // Offset verticale shadow layer.
    static let shadowLayerYOffset: CGFloat = 1
}


// MARK: - Shape condivisa

// Shape condivisa delle card grouped.
// Adatta dinamicamente gli angoli in base alla posizione della row.
struct TaskRowShape: InsettableShape {

    let position: TaskRowPosition
    var insetAmount: CGFloat = 0

    private var radius: CGFloat {
        TaskRowMetrics.groupedCornerRadius
    }

    private var middleRadius: CGFloat {
        TaskRowMetrics.groupedMiddleCornerRadius
    }

    func path(in rect: CGRect) -> Path {

        let shape: UnevenRoundedRectangle

        switch position {

        // Row singola isolata.
        case .single:

            shape = UnevenRoundedRectangle(
                topLeadingRadius: radius,
                bottomLeadingRadius: radius,
                bottomTrailingRadius: radius,
                topTrailingRadius: radius
            )

        // Prima row di un gruppo.
        case .first:

            shape = UnevenRoundedRectangle(
                topLeadingRadius: radius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: radius
            )

        // Row centrale di un gruppo.
        case .middle:

            shape = UnevenRoundedRectangle(
                topLeadingRadius: middleRadius,
                bottomLeadingRadius: middleRadius,
                bottomTrailingRadius: middleRadius,
                topTrailingRadius: middleRadius
            )

        // Ultima row di un gruppo.
        case .last:

            shape = UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: radius,
                bottomTrailingRadius: radius,
                topTrailingRadius: 0
            )
        }

        let insetRect = rect.insetBy(
            dx: insetAmount,
            dy: insetAmount
        )

        return shape.path(in: insetRect)
    }

    func inset(by amount: CGFloat) -> some InsettableShape {

        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

// MARK: - Helper condivisi

func isTaskToday(_ date: Date?) -> Bool {

    guard let date else {
        return false
    }

    return Calendar.current.isDateInToday(date)
}

func isTaskOverdue(_ date: Date?) -> Bool {

    guard let date else {
        return false
    }

    return date < Date()
}


// MARK: - Layout spacing condivisi

enum TaskRowLayout {

    // Distanza colonna data -> contenuto
    static let dateToContentSpacing: CGFloat = 10

    // Distanza colonna icona -> contenuto
    static let iconToContentSpacing: CGFloat = 10

    // Distanza contenuto -> icona trailing
    static let contentToTrailingSpacing: CGFloat = 10

    // Spaziatura interna standard
    static let contentSpacing: CGFloat = 8

    // Larghezza standard colonna icona
    static let iconColumnWidth: CGFloat = 44

    // Offset compensazione icone
    static let iconCompensationOffset: CGFloat = 0
}
