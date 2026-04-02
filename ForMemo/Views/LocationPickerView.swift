import SwiftUI
import MapKit
import CoreLocation
import Combine
import os



@MainActor
@Observable
final class LocationSearchCompleter: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
    
    private let completer = MKLocalSearchCompleter()
    
    override init() {
        super.init()
        completer.resultTypes = [.address, .pointOfInterest]
        completer.delegate = self
    }
    
    func update(query: String) {
        completer.queryFragment = query
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }
    
    func completer(
        _ completer: MKLocalSearchCompleter,
        didFailWithError error: Error
    ) {
        
        AppLogger.app.error("Completer error: \( error.localizedDescription)")
    }
}



struct LocationPickerView: View {
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var query = ""
    
    @State private var searchCompleter = LocationSearchCompleter()
    
    let onSelect: (String, CLLocationCoordinate2D) -> Void
    
    var body: some View {
        
        NavigationStack {
            
            List(searchCompleter.results, id: \.self) { item in
                Button {
                    resolve(item)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                        if !item.subtitle.isEmpty {
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Search location")
            .searchable(text: $query)
            .onChange(of: query) { _, newValue in
                searchCompleter.update(query: newValue)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.snappy) {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.primary)
                            .font(.title2)
                    }
                }
            }
        }
    }
    
    private func resolve(_ completion: MKLocalSearchCompletion) {
        
        let request = MKLocalSearch.Request(completion: completion)
        
        Task {
            let search = MKLocalSearch(request: request)
            let response = try? await search.start()
            
            guard let item = response?.mapItems.first else { return }
            
            let coordinate = item.location.coordinate
            let name = item.name ?? completion.title
            
            onSelect(name, coordinate)
            dismiss()
        }
    }
}

private struct CompleterWrapper: UIViewControllerRepresentable {
    
    let completer: MKLocalSearchCompleter
    @Binding var results: [MKLocalSearchCompletion]
    
    func makeCoordinator() -> Coordinator {
        Coordinator(results: $results)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        completer.delegate = context.coordinator
        return UIViewController()
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    final class Coordinator: NSObject, MKLocalSearchCompleterDelegate {
        
        @Binding var results: [MKLocalSearchCompletion]
        
        init(results: Binding<[MKLocalSearchCompletion]>) {
            _results = results
        }
        
        func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
            
            self.results = completer.results
            
        }
    }
}
