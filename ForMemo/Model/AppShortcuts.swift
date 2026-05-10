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
                AppShortcutPhrase("Check \(.applicationName)"),
                AppShortcutPhrase("Read \(.applicationName)"),

                // 🇮🇹 Italiano
                AppShortcutPhrase("Controlla \(.applicationName)"),
                AppShortcutPhrase("Leggi \(.applicationName)"),

                
                // 🇩🇪 Deutsch
                AppShortcutPhrase("Prüfe \(.applicationName)"),
                AppShortcutPhrase("Lies \(.applicationName)"),

                // 🇫🇷 Français
                AppShortcutPhrase("Montre \(.applicationName)"),
                AppShortcutPhrase("Lis \(.applicationName)"),

                // 🇪🇸 Español (España)
                AppShortcutPhrase("Comprueba \(.applicationName)"),
                AppShortcutPhrase("Lee \(.applicationName)")
            ],
            shortTitle: LocalizedStringResource("Get Tasks"),
            systemImageName: "checklist"
        )
        
        AppShortcut(
            intent: SearchTasksIntent(),
            phrases: [
                // 🇬🇧 English
                AppShortcutPhrase("Find \(.applicationName)"),
                AppShortcutPhrase("Search \(.applicationName)"),
                
                // 🇮🇹 Italiano
                AppShortcutPhrase("Trova \(.applicationName)"),
                AppShortcutPhrase("Cerca \(.applicationName)"),

                // 🇩🇪 Deutsch
                AppShortcutPhrase("Finde \(.applicationName)"),
                AppShortcutPhrase("Suche \(.applicationName)"),
                
                // 🇫🇷 Français
                AppShortcutPhrase("Trouve \(.applicationName)"),
                AppShortcutPhrase("Cherche \(.applicationName)"),
                
                // 🇪🇸 Español (España)
                AppShortcutPhrase("Encuentra \(.applicationName)"),
                AppShortcutPhrase("Busca \(.applicationName)")
                
            ],
            shortTitle: LocalizedStringResource("Search Tasks"),
            systemImageName: "magnifyingglass"
        )
    }
    
    static var shortcutTileColor: ShortcutTileColor = .blue
}
