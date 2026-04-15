import SwiftUI
import EventKit

struct CalendarPickerView: View {
    
    let calendars: [EKCalendar]
    let onSelect: (EKCalendar) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List(calendars, id: \.calendarIdentifier) { calendar in
                
                Button {
                    onSelect(calendar)
                    dismiss()
                } label: {
                    HStack {
                        Circle()
                            .fill(Color(calendar.cgColor))
                            .frame(width: 12, height: 12)
                        
                        Text(calendar.title)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Select Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
