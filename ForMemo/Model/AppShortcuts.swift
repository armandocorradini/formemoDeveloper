import AppIntents

struct AppShortcuts: AppShortcutsProvider {
    
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                // 🇬🇧 English
                AppShortcutPhrase("New \(.applicationName)"),

                // 🇮🇹 Italiano
                AppShortcutPhrase("Nuovo \(.applicationName)"),

                // 🇩🇪 Deutsch
                AppShortcutPhrase("Neu \(.applicationName)"),

                // 🇫🇷 Français
                AppShortcutPhrase("Nouveau \(.applicationName)"),

                // 🇪🇸 Español (España)
                AppShortcutPhrase("Nuevo \(.applicationName)")
            ],
            shortTitle: LocalizedStringResource("Add Task"),
            systemImageName: "plus.circle.fill"
        )
        
        AppShortcut(
            intent: GetTasksIntent(),
            phrases: [
                // 🇬🇧 English
                AppShortcutPhrase("Read \(.applicationName)"),

                // 🇮🇹 Italiano
                AppShortcutPhrase("Leggi \(.applicationName)"),

                // 🇩🇪 Deutsch
                AppShortcutPhrase("Lies \(.applicationName)"),

                // 🇫🇷 Français
                AppShortcutPhrase("Lire \(.applicationName)"),

                // 🇪🇸 Español (España)
                AppShortcutPhrase("Leer \(.applicationName)")
            ],
            shortTitle: LocalizedStringResource("Get Tasks"),
            systemImageName: "checklist"
        )
        
        AppShortcut(
            intent: SearchTasksIntent(),
            phrases: [
                // 🇬🇧 English
                AppShortcutPhrase("Search \(.applicationName)"),

                // 🇮🇹 Italiano
                AppShortcutPhrase("Cerca \(.applicationName)"),

                // 🇩🇪 Deutsch
                AppShortcutPhrase("Suche \(.applicationName)"),

                // 🇫🇷 Français
                AppShortcutPhrase("Rechercher \(.applicationName)"),

                // 🇪🇸 Español (España)
                AppShortcutPhrase("Buscar \(.applicationName)")
            ],
            shortTitle: LocalizedStringResource("Search Tasks"),
            systemImageName: "magnifyingglass"
        )
    }
    
    static var shortcutTileColor: ShortcutTileColor = .blue
}
