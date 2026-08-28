import AppIntents

struct AppShortcuts: AppShortcutsProvider {
    
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                // 🇬🇧 English
                AppShortcutPhrase("New \(.applicationName)"),
                AppShortcutPhrase("Add \(.applicationName)"),

                // 🇮🇹 Italiano
                AppShortcutPhrase("Nuovo \(.applicationName)"),
                AppShortcutPhrase("Aggiungi \(.applicationName)"),

                // 🇩🇪 Deutsch
                AppShortcutPhrase("Neu \(.applicationName)"),
                AppShortcutPhrase("Hinzufügen \(.applicationName)"),

                // 🇫🇷 Français
                AppShortcutPhrase("Nouveau \(.applicationName)"),
                AppShortcutPhrase("Ajouter \(.applicationName)"),

                // 🇪🇸 Español (España)
                AppShortcutPhrase("Nuevo \(.applicationName)"),
                AppShortcutPhrase("Añadir \(.applicationName)")
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
                AppShortcutPhrase("Report \(.applicationName)"),

                // 🇮🇹 Italiano
                AppShortcutPhrase("Controlla \(.applicationName)"),
                AppShortcutPhrase("Leggi \(.applicationName)"),
                AppShortcutPhrase("Report \(.applicationName)"),

                
                // 🇩🇪 Deutsch
                AppShortcutPhrase("Prüfe \(.applicationName)"),
                AppShortcutPhrase("Lies \(.applicationName)"),
                AppShortcutPhrase("Bericht \(.applicationName)"),

                // 🇫🇷 Français
                AppShortcutPhrase("Montre \(.applicationName)"),
                AppShortcutPhrase("Lis \(.applicationName)"),
                AppShortcutPhrase("Rapport \(.applicationName)"),

                // 🇪🇸 Español (España)
                AppShortcutPhrase("Comprueba \(.applicationName)"),
                AppShortcutPhrase("Lee \(.applicationName)"),
                AppShortcutPhrase("Informe \(.applicationName)")
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
        
        AppShortcut(
            intent: AddNoteIntent(),
            phrases: [
                // English
                AppShortcutPhrase("Write a note in \(.applicationName)"),
                AppShortcutPhrase("Write in \(.applicationName)"),
                AppShortcutPhrase("Add a note to \(.applicationName)"),
                AppShortcutPhrase("Note in \(.applicationName)"),
                AppShortcutPhrase("Note \(.applicationName)"),
                AppShortcutPhrase("Take a note in \(.applicationName)"),
                AppShortcutPhrase("Take a note with \(.applicationName)"),
                AppShortcutPhrase("Memo in \(.applicationName)"),

                // Italiano
//                AppShortcutPhrase("Scrivi nota in \(.applicationName)"),
                AppShortcutPhrase("Scrivi in \(.applicationName)"),
                AppShortcutPhrase("Aggiungi nota a \(.applicationName)"),
                AppShortcutPhrase("Nota in \(.applicationName)"),
                AppShortcutPhrase("Nota \(.applicationName)"),
                AppShortcutPhrase("Annota in \(.applicationName)"),
                AppShortcutPhrase("Annota con \(.applicationName)"),
                AppShortcutPhrase("Memo in \(.applicationName)"),

                // Deutsch
                AppShortcutPhrase("Schreibe eine Notiz in \(.applicationName)"),
                AppShortcutPhrase("Schreibe in \(.applicationName)"),
                AppShortcutPhrase("Füge eine Notiz zu \(.applicationName) hinzu"),
                AppShortcutPhrase("Notiz in \(.applicationName)"),
                AppShortcutPhrase("Notiz \(.applicationName)"),
                AppShortcutPhrase("Notiere in \(.applicationName)"),
                AppShortcutPhrase("Notiere mit \(.applicationName)"),
                AppShortcutPhrase("Memo in \(.applicationName)"),

                // Français
                AppShortcutPhrase("Écris une note dans \(.applicationName)"),
                AppShortcutPhrase("Écris dans \(.applicationName)"),
                AppShortcutPhrase("Ajoute une note à \(.applicationName)"),
                AppShortcutPhrase("Note dans \(.applicationName)"),
                AppShortcutPhrase("Note \(.applicationName)"),
                AppShortcutPhrase("Prends une note dans \(.applicationName)"),
                AppShortcutPhrase("Prends une note avec \(.applicationName)"),
                AppShortcutPhrase("Mémo dans \(.applicationName)"),

                // Español (España)
                AppShortcutPhrase("Escribe una nota en \(.applicationName)"),
                AppShortcutPhrase("Escribe en \(.applicationName)"),
                AppShortcutPhrase("Añade una nota a \(.applicationName)"),
                AppShortcutPhrase("Nota en \(.applicationName)"),
                AppShortcutPhrase("Nota \(.applicationName)"),
                AppShortcutPhrase("Toma una nota en \(.applicationName)"),
                AppShortcutPhrase("Toma una nota con \(.applicationName)"),
                AppShortcutPhrase("Nota en \(.applicationName)")
            ],
            shortTitle: LocalizedStringResource("Note ForMemo"),
            systemImageName: "note.text.badge.plus"
        )
        
    }
    
    static var shortcutTileColor: ShortcutTileColor = .blue
}
