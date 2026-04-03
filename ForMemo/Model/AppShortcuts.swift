import AppIntents

struct AppShortcuts: AppShortcutsProvider {
    
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                // 🇬🇧 English
                AppShortcutPhrase("Add a task in \(.applicationName)"),
                AppShortcutPhrase("Create a task in \(.applicationName)"),
                AppShortcutPhrase("Remind me in \(.applicationName)"),
                
                // 🇮🇹 Italiano
                AppShortcutPhrase("Aggiungi promemoria in \(.applicationName)"),
                AppShortcutPhrase("Crea promemoria in \(.applicationName)"),
                AppShortcutPhrase("Promemoria in \(.applicationName)"),
                
                // 🇩🇪 Deutsch
                AppShortcutPhrase("Füge eine Aufgabe in \(.applicationName) hinzu"),
                AppShortcutPhrase("Erstelle eine Aufgabe in \(.applicationName)"),
                AppShortcutPhrase("Erinnere mich in \(.applicationName)"),
                
                // 🇫🇷 Français
                AppShortcutPhrase("Ajouter une tâche dans \(.applicationName)"),
                AppShortcutPhrase("Créer une tâche dans \(.applicationName)"),
                AppShortcutPhrase("Rappelle-moi dans \(.applicationName)"),
                
                // 🇪🇸 Español (España)
                AppShortcutPhrase("Añade una tarea en \(.applicationName)"),
                AppShortcutPhrase("Crea una tarea en \(.applicationName)"),
                AppShortcutPhrase("Recordatorio en \(.applicationName)")
            ],
            shortTitle: LocalizedStringResource("Add Task"),
            systemImageName: "plus.circle.fill"
        )
    }
    
    static var shortcutTileColor: ShortcutTileColor = .blue
}
