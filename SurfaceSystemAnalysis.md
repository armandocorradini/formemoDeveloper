# Surface System Analysis

Ho fatto l'analisi in sola lettura. Nessun file modificato.

## Verdetto

Il Surface System reale oggi non e' globale. E' un sistema quasi esclusivamente task-row, centrato su:

- `ForMemo/ForMemo/Model/TaskRowSurface.swift`
- `ForMemo/ForMemo/Model/TaskRowAppearance.swift`
- i wrapper applicativi dentro `ForMemo/ForMemo/Views/TaskListView.swift` e `ForMemo/ForMemo/Views/WeeklyTasksView.swift`

`AppSurface.swift` e' vuoto. Quindi non e' il centro del sistema.

## Mappa

| View | Tipo | Radius | Border | Shadow | Material | Duplicazioni |
|---|---|---:|---|---|---|---|
| `TaskRowSurface` | renderer row | da shape | no, separator/highlight overlay | si | no | centro |
| `TaskRowShape` | shape group | 22 / 0.5 / 0 | no | no | no | sorgente radius task |
| `TodoSectionView.RowCardStyle` | applicatore row/group | `TaskRowShape` | no | via surface | no | dup con completed/weekly |
| `CompletedSectionView.RowCardStyle` | applicatore row/group | `TaskRowShape` | no | via surface | no | dup parziale |
| `WeeklyTaskRow.cardBackground` | applicatore row/group | `TaskRowShape` | no | via surface | no | dup forte |
| `TaskRow` | contenuto navigabile | no | no | no | no | corretto |
| `TaskRowContent` | contenuto row | no | no | no | no | non surface |
| `TaskListAppearanceView.previewRow` | preview row | via `TodoSectionView.RowCardStyle` | no | via surface | no | corretta |
| `DocumentsView` | standard row | List/SwiftUI | List | List | no | bg locale `.opacity(0.3)` |
| `DocumentDetailView` | standard group/form | List/Form | List | List | no | bg locale `.opacity(0.3)` |
| `TaskDetailView` sections | standard group/form | List/Form | List | List | no | bg locale nelle subview |
| `MainInfoSection` | standard group | List/Form | List | List | no | bg locale + highlight locale |
| `ScheduleSection` | standard group | List/Form | locale su DatePicker | List | no | bg locale |
| `ContextSection` | standard group | List/Form | List | List | no | bg locale |
| `ResourcesSection` | standard group | List/Form | List | List | no | bg locale |
| `AttachmentRow` | row content | no | no | no | no | corretto |
| `AudioPlayerRow` | control | no | no | no | no | fuori sistema |
| `NewTaskSheetView` | standard groups | List default | List | List | no | simile a detail ma non custom |
| `TravelKitListView` | standard row | List/SwiftUI | List | List | no | bg locale `.opacity(0.3)` |
| `TripChecklistView` | standard row/group | List/SwiftUI | header custom 12 | header line | List | bg locale |
| `WalletView` | standard row | List/SwiftUI | List | List | no | bg locale; thumbnail custom escluso |
| `LoyaltyCardDetailView` | card/detail | custom | custom | custom | no | fuori row/group |
| `Dashboard.sectionCard` | dashboard card | 16 | stroke 0.10 | si | regularMaterial | fuori Surface System |
| `OverviewView` sections | dashboard group card | 16 | stroke 0.10 | si | regularMaterial | fuori Surface System |
| `ImportCard` | import card | 18 | selected stroke | si | no | fuori Surface System |
| `ReminderRow` / `EventRow` | import rows | standard | standard | standard | no | non centrale |

## Duplicazioni

### A. Corrette

Row standard in `Documents`, `Trips`, `Wallet`, `TaskDetail`, `NewTaskSheet`. Sono List/Form native; SwiftUI deve possedere radius/border/shadow.

### B. Da eliminare

Tre applicatori task-row separati:

- `TodoSectionView.RowCardStyle`
- `CompletedSectionView.RowCardStyle`
- `WeeklyTaskRow.cardBackground`

### C. Dovute all'architettura

`TaskRowSurface` e' centrale, ma la decisione di shape, separator, highlight, opacity e posizione vive nei call-site. Quindi il renderer disegna, ma non governa il sistema.

### D. Inevitabili

Thumbnail, barcode, dashboard cards, weather cards, capsule header, badge, map annotations. Non sono row/group.

## Responsabilita'

| Responsabilita' | Proprietario corretto | Proprietario attuale | Stato |
|---|---|---|---|
| Fill row task | `TaskRowSurface` | `TaskRowSurface` | corretto |
| Shadow row task | `TaskRowSurface` + `TaskRowTheme` | `TaskRowSurface` | corretto |
| Radius row task | `TaskRowShape` / `TaskRowMetrics` | `TaskRowShape` | corretto |
| Posizione first/middle/last | container di lista | `TaskListView`, `WeeklyTasksView`, `CompletedSectionView` | corretto ma duplicato |
| Applicazione `listRowBackground` | adapter List-row | tre luoghi diversi | nel posto sbagliato |
| Material row standard | SwiftUI List/Form | SwiftUI + bg locale | accettabile |
| App background glass | app shell | `AppGlassBackground` | fuori sistema |
| Contenuto row | singola row | `TaskRowContent`, domain views | corretto |

## Sorgenti di verita'

Corner radius task: esiste, `TaskRowMetrics.groupedCornerRadius`, `plainCornerRadius`, `groupedMiddleCornerRadius`.

Shadow task: esiste quasi, ma divisa tra `TaskRowTheme.shadow` e `TaskRowRendering`. E' una sorgente funzionale, non pulita.

Border task: non esiste come border. Esistono separator e highlight overlay. I border veri sono locali e fuori task surface.

## Coerenza SwiftUI

Non stai combattendo SwiftUI quando lasci `List`, `Form` e `Section` disegnare Documents/Trips/Wallet/Detail.

Stai invece introducendo attrito quando provi a far diventare globale un sistema nato per task-row custom.

I livelli necessari sono:

- shape/metrics
- surface renderer
- adapter per `List`
- content row

I livelli non necessari sono duplicati di adapter e un eventuale `AppSurface` generico se deve coprire cose non assimilabili.

## Risposte obbligatorie

### A. Qual e' il vero centro del Surface System?

Il vero centro del Surface System e' `TaskRowSurface`, ma il centro operativo e' `TodoSectionView.RowCardStyle`, perche' decide come il renderer entra in `List`.

### B. Qual e' il primo file da modificare?

Primo file da modificare: `TaskListView.swift`.

Motivo: contiene il wrapper principale e la duplicazione completed. E' il punto con piu' rischio e piu' valore.

### C. Quale file NON deve essere toccato?

File da non toccare: `TaskRowContent.swift`.

Motivo: e' contenuto/layout della row, non surface. Toccarlo confonderebbe refactor visivo e refactor strutturale.

### D. Qual e' la roadmap con il rischio minore?

1. `TaskListView.swift`
2. `WeeklyTasksView.swift`
3. `TaskListAppearanceView.swift`
4. Solo dopo valutare `DocumentsView`, `TripsView`, `WalletView`, `TaskDetailSection/*`

`Dashboard` e `Overview` restano fuori.

### E. Esistono parti del progetto che NON appartengono al Surface System?

Si:

- `AppGlassBackground`
- capsule header
- badge
- search bar
- tab bar
- toolbar
- weather
- map annotations
- barcode/card detail
- thumbnail/logo
- import cards

### F. Da Senior Engineer Apple, rifarei completamente questa architettura oppure la rifattorizzerei progressivamente?

Non rifarei tutto. Rifattorizzerei progressivamente.

Il sistema task-row ha gia' un buon nucleo; il problema non e' il renderer, e' che l'adapter verso `List` e' duplicato e il confine con le row standard non e' dichiarato.

Una riscrittura totale aumenterebbe rischio e probabilmente combatterebbe SwiftUI.
