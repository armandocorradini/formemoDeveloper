import AppIntents
import SwiftUI
import SwiftData
import Foundation

// MARK: - Intent

struct AddTaskIntent: AppIntent {
    
    static var title: LocalizedStringResource = "Add Task"
    static var description = IntentDescription("Add a task using natural language.")
    
    @AppStorage("notificationLeadTimeDays")
    private var notificationLeadTimeDays: Int = 1
    
    // MARK: - Parameters
    
    @Parameter(
        title: "Task",
        requestValueDialog: IntentDialog("What do you want to add?")
    )
    var input: String
    
    @Parameter(
        title: "Date",
        requestValueDialog: IntentDialog("When should I schedule it?")
    )
    var date: Date?
    
    @Parameter(
        title: "Reminder",
        requestValueDialog: IntentDialog("Do you want a reminder? If yes, when?")
    )
    var reminderText: String?
    
    
    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$input) at \(\.$date) with reminder \(\.$reminderText)")
    }
    
    // MARK: - Init
    
    init() {}
    
    init(input: String, date: Date? = nil) {
        self.input = input
        
        let parsed = NaturalLanguageParser.parse(input)
        
        if let parsedDate = parsed.date {
            self.date = parsedDate
        } else if let date {
            self.date = date
        } else {
            self.date = nil // 🔥 fondamentale per far chiedere Siri
        }
    }
    
    // MARK: - Perform
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(Persistence.shared)
//        let context = Persistence.shared.mainContext
        let now = Date()
        
        let parsed = NaturalLanguageParser.parse(input)
        let finalTitle = parsed.title
        
        let dueDate = date ?? parsed.date
        
        guard let dueDate else {
            throw $date.needsValueError()
        }
        
        guard dueDate > now else {
            return .result(dialog: IntentDialog("That time is in the past."))
        }
        
        let task = TodoTask(title: finalTitle, deadLine: dueDate)
        
        if let inferredTag = TagInference.infer(from: finalTitle) {
            task.mainTag = inferredTag
        }
        
        let autoReminderEnabled = UserDefaults.standard.bool(forKey: "siriAutoReminderEnabled")
        
        var reminderInfo: String
        
        // MARK: - AUTO
        
        if autoReminderEnabled {
            
            let reminder = Self.computeReminder(
                now: now,
                deadline: dueDate,
                leadTimeDays: notificationLeadTimeDays
            )
            
            task.reminderOffsetMinutes = reminder.offsetMinutes
            reminderInfo = reminder.info
            
        }
        
        // MARK: - MANUAL (Siri)
        
        else {
            
            // 🔥 Apple style: UNA domanda sola
            
            guard let reminderText, !reminderText.isEmpty else {
                throw $reminderText.needsValueError()
            }
            
            let normalized = reminderText
                .folding(options: .diacriticInsensitive, locale: .current)
                .lowercased()
            
            let minutes: Int?

            // MARK: - NONE

            let words = normalized.components(separatedBy: CharacterSet.whitespacesAndNewlines)

            let noKeywords = [
                "no", "none",
                "nessun", "nessuno", "niente",
                "aucun",
                "ningun",
                "kein"
            ]

            if words.contains(where: { word in
                noKeywords.contains(word)
            }) {
                minutes = nil
            }

            // MARK: - AT DEADLINE

            else if [
                // EN
                "when it's due", "when it is due", "at the deadline",
                "at due time", "only when due",

                // IT
                "alla scadenza", "alla fine", "al termine",
                "solo alla fine", "solo alla scadenza",

                // FR
                "à l'échéance", "au moment de l'échéance",
                "seulement à l'échéance",

                // ES
                "al vencimiento", "en el momento exacto",
                "solo al vencimiento",

                // DE
                "bei fälligkeit", "zum fälligkeitszeitpunkt",
                "nur bei fälligkeit"
            ].contains(where: { normalized.contains($0) }) {
                minutes = nil
            }

            // MARK: - SPECIAL DURATIONS (no numbers)

            // HALF HOUR (30 min)
            else if [
                // EN
                "half an hour", "half hour",
                // IT
                "mezzora", "mezz ora", "mezz'ora",
                // FR
                "demi heure", "demi-heure", "une demi heure",
                // ES
                "media hora",
                // DE
                "halbe stunde", "eine halbe stunde"
            ].contains(where: { normalized.contains($0) }) {
                minutes = 30
            }

            // QUARTER HOUR (15 min)
            else if [
                // EN
                "quarter of an hour", "a quarter hour", "quarter hour",
                // IT
                "un quarto d ora", "un quarto d'ora", "un quarto ora",
                // FR
                "un quart d heure", "un quart d'heure",
                // ES
                "un cuarto de hora",
                // DE
                "viertelstunde"
            ].contains(where: { normalized.contains($0) }) {
                minutes = 15
            }

            // THREE QUARTERS (45 min)
            else if [
                // EN
                "three quarters of an hour", "three quarter hour",
                // IT
                "tre quarti d ora", "tre quarti d'ora",
                // FR
                "trois quarts d heure", "trois quarts d'heure",
                // ES
                "tres cuartos de hora",
                // DE
                "dreiviertelstunde"
            ].contains(where: { normalized.contains($0) }) {
                minutes = 45
            }

            // MARK: - MINUTES
            
            else if normalized.contains("min") {
                guard let value = extractNumber(from: normalized) else {
                    throw $reminderText.needsValueError()
                }
                minutes = max(1, min(59, value))
            }
            
            // MARK: - HOURS
            
            else if [
                "hour", "hours", "ora", "ore",
                "heure", "heures",
                "hora", "horas",
                "stunde", "stunden"
            ].contains(where: { normalized.contains($0) }) {
                
                guard let value = extractNumber(from: normalized) else {

                    throw $reminderText.needsValueError()
                }
                let clamped = max(1, min(23, value))
                minutes = clamped * 60
            }
            
            // MARK: - DAYS
            
            else if [
                "day", "days",
                "giorno", "giorni",
                "dia", "dias",
                "jour", "jours",
                "tag", "tage"
            ].contains(where: { normalized.contains($0) }) {
                
                guard let value = extractNumber(from: normalized) else {
                    throw $reminderText.needsValueError()
                }
                let clamped = max(1, min(7, value))
                minutes = clamped * 1440
            }
            
            // MARK: - FALLBACK
            
            else {
                throw $reminderText.needsValueError()
            }
            
            // 🔥 APPLY (coerente con ReminderScrubberControl)
            
            task.reminderOffsetMinutes = minutes
            
            if minutes == nil {
                reminderInfo = String(localized: "when it's due")
            } else {
                reminderInfo = Self.description(forMinutes: minutes!)
            }
        }

        context.insert(task)
        try context.save()
        
        NotificationManager.shared.refresh()
        
        let shortResponse = UserDefaults.standard.bool(forKey: "siriShortConfirmation")
        
        if shortResponse {
            return .result(dialog: "Done")
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let formattedDate = formatter.string(from: dueDate)
        let at = String(localized: "date.at")
        let spokenDate = formattedDate.replacingOccurrences(of: ", ", with: " \(at) ")

        if task.reminderOffsetMinutes == nil {
            return .result(
                dialog: IntentDialog("Done. \(finalTitle) is scheduled for \(spokenDate). You’ll get a notification when it’s due.")
            )
        }

        return .result(
            dialog: IntentDialog("Done. \(finalTitle) is scheduled for \(spokenDate). I’ll remind you \(reminderInfo), and again when it’s due.")
        )
    }
}

func extractNumber(from text: String) -> Int? {
    
    let numbers = text.components(separatedBy: CharacterSet.decimalDigits.inverted)
    if let first = numbers.first(where: { !$0.isEmpty }),
       let value = Int(first) {
        return value
    }
    
    let formatter = NumberFormatter()
    formatter.numberStyle = .spellOut
    
    let locales = [
        "en_US", "it_IT", "fr_FR", "es_ES", "de_DE"
    ]
    
    let words = text
        .lowercased()
        .replacingOccurrences(of: "'", with: " ")
        .components(separatedBy: CharacterSet.whitespacesAndNewlines)
    
    for localeID in locales {
        formatter.locale = Locale(identifier: localeID)
        
        for word in words {
            if let number = formatter.number(from: word) {
                return number.intValue
            }
        }
    }
    
    return nil // 🔴 NON più 0
}

struct NaturalLanguageParser {
    
    struct Result {
        let title: String
        let date: Date?
    }
    
    static func parse(_ input: String) -> Result {
        
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let nsRange = NSRange(input.startIndex..., in: input)
        
        var detectedDate: Date?
        var cleaned = input
        
        if let match = detector?.firstMatch(in: input, options: [], range: nsRange),
           let date = match.date {
            
            detectedDate = date
            
            if let range = Range(match.range, in: input) {
                cleaned.removeSubrange(range)
            }
        }
        
        let stopWords = [
            "add", "create", "remind me", "schedule",
            "aggiungi", "crea", "ricordami", "segnami", "metti",
            "añade", "crea", "recordatorio", "apunta", "pon",
            "ajoute", "crée", "rappelle-moi", "planifie",
            "hinzufügen", "erstelle", "erinnere mich", "plane"
        ]
        
        var title = cleaned.lowercased()
        
        for word in stopWords {
            title = title.replacingOccurrences(of: word, with: "")
        }
        
        title = title
            .replacingOccurrences(of: "[^a-zA-Z0-9àèéìòù ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return Result(
            title: title.isEmpty ? input.capitalized : title.capitalized,
            date: detectedDate
        )
    }
}

private extension AddTaskIntent {
    
    static func computeReminder(
        now: Date,
        deadline: Date,
        leadTimeDays: Int
    ) -> (offsetMinutes: Int?, info: String) {
        
        let secondsRemaining = deadline.timeIntervalSince(now)
        
        guard secondsRemaining > 0 else {
            return (0, description(forMinutes: 0))
        }
        
        let calendar = Calendar.autoupdatingCurrent
        let currentHour = calendar.component(.hour, from: now)
        let deadlineHour = calendar.component(.hour, from: deadline)
        
        // 🔥 1. Se la scadenza è di notte → niente anticipo
        if deadlineHour >= 22 || deadlineHour < 7 {
            return (0, description(forMinutes: 0))
        }
        
        // 🔥 2. Regole base
        let rules: [(threshold: TimeInterval, offsetHours: Int)] = [
            (3600, 0),
            (4 * 3600, 1),
            (12 * 3600, 3),
            (24 * 3600, 6),
            (48 * 3600, 12),
            (7 * 24 * 3600, 24),
            (Double.infinity, 168)
        ]
        
        var baseOffsetHours = rules
            .first(where: { secondsRemaining <= $0.threshold })?
            .offsetHours ?? 0
        
        // 🔧 Personalizzazione utente
        if leadTimeDays == 0 {
            baseOffsetHours = (secondsRemaining > 3600) ? 1 : 0
        } else {
            let maxAllowedHours = leadTimeDays * 24
            baseOffsetHours = min(baseOffsetHours, maxAllowedHours)
            
            if baseOffsetHours == maxAllowedHours && baseOffsetHours > 0 {
                baseOffsetHours -= min(6, baseOffsetHours)
            }
        }
        
        // 🔥 Se offset supera il tempo → annulla
        if Double(baseOffsetHours * 3600) >= secondsRemaining {
            baseOffsetHours = 0
        }
        
        guard baseOffsetHours > 0 else {
            return (0, description(forMinutes: 0))
        }
        
        // 🔥 Calcolo reminder teorico
        guard let baseReminderDate = calendar.date(
            byAdding: .hour,
            value: -baseOffsetHours,
            to: deadline
        ) else {
            return (baseOffsetHours * 60, description(forMinutes: baseOffsetHours * 60))
        }
        
        // 🔥 3. Se reminder cade di notte
        if isNight(date: baseReminderDate, calendar: calendar) {
            
            // Se siamo già di notte → niente anticipo
            if currentHour < 7 {
                return (0, description(forMinutes: 0))
            }
        }
        
        // 🔥 4. Adattamento fascia 7–21
        let adjustedReminderDate = adjustedDateAvoidingNight(
            from: baseReminderDate,
            deadline: deadline,
            calendar: calendar
        )
        
        let finalReminderDate = adjustedReminderDate ?? baseReminderDate
        
        // 🔥 5. Evita passato
        guard finalReminderDate > now else {
            return (0, description(forMinutes: 0))
        }
        
        let offsetMinutes = max(
            Int(deadline.timeIntervalSince(finalReminderDate) / 60),
            0
        )

        if leadTimeDays > 0 {

            let globalOffsetMinutes = leadTimeDays * 1440

            if offsetMinutes == globalOffsetMinutes {
                return (nil, String(localized: "when it's due"))
            }
        }

        return (offsetMinutes, description(forMinutes: offsetMinutes))
    }
    
    static func isNight(date: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= 22 || hour < 7
    }
    
    static func adjustedDateAvoidingNight(
        from date: Date,
        deadline: Date,
        calendar: Calendar
    ) -> Date? {
        
        let startHour = 7
        let endHour = 21
        
        let hour = calendar.component(.hour, from: date)
        
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        
        // Caso notte tarda → porta a 21 stesso giorno
        if hour >= endHour {
            components.hour = endHour
            components.minute = 0
            
            guard let candidate = calendar.date(from: components),
                  candidate < deadline else {
                return nil
            }
            
            return candidate
        }
        
        // Caso notte mattina → porta alle 7
        if hour < startHour {
            components.hour = startHour
            components.minute = 0
            
            guard let candidate = calendar.date(from: components),
                  candidate < deadline else {
                return nil
            }
            
            return candidate
        }
        
        return date
    }
    
    
    static func description(forMinutes minutes: Int) -> String {
        
        if minutes == 0 {
            return String(localized: "at time of event")
        }
        
        if minutes < 60 {
            return String(localized: "\(minutes) minutes before")
        }
        
        let hours = minutes / 60
        
        if hours == 1 {
            return String(localized: "one hour before")
        }
        
        if hours < 24 {
            return String(localized: "\(hours) hours before")
        }
        
        let days = hours / 24
        
        return days == 1
        ? String(localized: "1 day before")
        : String(localized: "\(days) days before")
    }
}

 enum TagInference {
    
    static let keywords: [TaskMainTag: [String]] = [
        
        .work: [
            // EN
            "work","job","office","meeting","client","project","email","call","deadline","report","business","team","manager","presentation","task",
            "conference","agenda","contract","invoice","salary","colleague","boss","appointment","planning","strategy","analysis","review",
            "briefing","schedule","milestone","startup","company","corporate","proposal","document","spreadsheet","excel","powerpoint",
            "zoom","teams","slack","followup","deliverable","workflow","budget","forecast","marketing","sales","support","ticket",
            
            // IT
            "lavoro","ufficio","riunione","cliente","progetto","email","chiamata","scadenza","relazione","azienda","team","manager","presentazione",
            "contratto","fattura","stipendio","collega","capo","appuntamento","pianificazione","strategia","analisi","revisione","agenda",
            "documento","bilancio","marketing","vendite","assistenza","ticket",
            
            // FR / ES / DE
            "travail","bureau","réunion","client","projet","email","appel","rapport",
            "trabajo","oficina","cliente","proyecto","correo","llamada","informe",
            "arbeit","büro","kunde","projekt","email","anruf","bericht"
        ],
        
        .health: [
            // EN
            "doctor","health","dentist","pharmacy","medicine","gym","workout","exercise","fitness","therapy","hospital","checkup",
            "diet","nutrition","vitamins","injury","pain","rehab","massage","yoga","running","training","wellness","clinic",
            "appointment","prescription","treatment","mental","psychologist","physio",
            
            // IT
            "medico","salute","dentista","farmacia","medicina","palestra","allenamento","esercizio","terapia","ospedale",
            "dieta","nutrizione","vitamine","dolore","riabilitazione","massaggio","yoga","corsa","clinica",
            "psicologo","fisioterapia",
            
            // FR / ES / DE
            "médecin","santé","dentiste","pharmacie","hôpital",
            "médico","salud","dentista","farmacia","hospital",
            "arzt","gesundheit","zahnarzt","apotheke","krankenhaus"
        ],
        
        .home: [
            // EN
            "home","house","clean","cleaning","groceries","shopping","cook","kitchen","laundry","bills","repair","maintenance",
            "rent","mortgage","utilities","electricity","water","gas","internet","wifi","furniture","garden","plants","tools",
            "vacuum","dishwasher","fridge","oven","bedroom","bathroom",
            
            // IT
            "casa","pulizie","spesa","cucinare","lavatrice","bollette","riparare","manutenzione",
            "affitto","mutuo","utenze","luce","acqua","gas","internet","wifi","mobili","giardino","piante",
            "aspirapolvere","lavastoviglie","frigo","forno",
            
            // FR / ES / DE
            "maison","ménage","courses","cuisine","factures",
            "casa","limpieza","compras","cocinar","facturas",
            "haus","putzen","einkaufen","kochen","rechnungen"
        ],
        
        .family: [
            // EN
            "family","parents","kids","children","wife","husband","mom","dad","brother","sister","birthday",
            "anniversary","school","homework","baby","grandparents","uncle","aunt","cousin","celebration",
            
            // IT
            "famiglia","genitori","figli","moglie","marito","mamma","papà","compleanno",
            "anniversario","scuola","compiti","bambino","nonni","zio","zia","cugino","festa",
            
            // FR / ES / DE
            "famille","parents","enfants","anniversaire",
            "familia","padres","niños","cumpleaños",
            "familie","eltern","kinder","geburtstag"
        ],
        
        .travel: [
            // EN
            "travel","trip","flight","hotel","booking","airport","vacation","holiday","tour","luggage",
            "ticket","passport","visa","boarding","departure","arrival","reservation","guide","map","destination",
            "airbnb","checkin","checkout","itinerary",
            
            // IT
            "viaggio","volo","hotel","prenotazione","aeroporto","vacanza","tour",
            "biglietto","passaporto","visto","partenza","arrivo","destinazione","guida",
            "checkin","checkout","itinerario",
            
            // FR / ES / DE
            "voyage","vol","hôtel","aéroport",
            "viaje","vuelo","hotel","aeropuerto",
            "reise","flug","hotel","flughafen"
        ],
        
        .transport: [
            // EN
            "car","train","bus","metro","taxi","uber","drive","parking","fuel","ticket",
            "license","traffic","road","highway","garage","mechanic","service","engine","insurance",
            "ride","commute","transport","vehicle",
            
            // IT
            "auto","treno","bus","metro","taxi","guidare","parcheggio","benzina","biglietto",
            "patente","traffico","strada","autostrada","garage","meccanico","assicurazione",
            
            // FR / ES / DE
            "voiture","train","bus","métro","taxi",
            "coche","tren","bus","metro","taxi",
            "auto","zug","bus","metro","taxi"
        ],
        
        .pet: [
            // EN
            "dog","cat","pet","vet","food","walk","litter","animal",
            "grooming","toy","leash","vaccination","care","feeding","training","puppy","kitten",
            
            // IT
            "cane","gatto","animale","veterinario","cibo","passeggiata",
            "toelettatura","giocattolo","guinzaglio","vaccino","cura","cucciolo",
            
            // FR / ES / DE
            "chien","chat","animal","vétérinaire",
            "perro","gato","animal","veterinario",
            "hund","katze","tier","tierarzt"
        ],
        
        .freetime: [
            // EN
            "movie","cinema","music","concert","game","sport","hobby","relax","party","dinner","friends",
            "bar","restaurant","drink","beer","wine","festival","event","show","netflix","tv","series","gaming",
            "weekend","outing","fun","club",
            
            // IT
            "film","cinema","musica","concerto","gioco","sport","hobby","relax","festa","cena","amici",
            "bar","ristorante","bere","birra","vino","evento","serie","tv","weekend",
            
            // FR / ES / DE
            "film","cinéma","musique","concert","fête",
            "película","cine","música","concierto","fiesta",
            "film","kino","musik","konzert","party"
        ]
    ]
    
    static func infer(from text: String) -> TaskMainTag? {
        
        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
        
        var scores: [TaskMainTag: Int] = [:]
        
        for (tag, keywords) in keywords {
            
            let matchCount = words.filter { word in
                keywords.contains(word)
            }.count
            
            if matchCount > 0 {
                scores[tag] = matchCount
            }
        }
        
        return scores.max(by: { $0.value < $1.value })?.key
    }
}
