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
    
    @State private var userLocation: CLLocation?
    @State private var locationDelegate: LocationDelegate?

    @State private var locationManager = CLLocationManager()
    
    
    
    let onSelect: (String, CLLocationCoordinate2D) -> Void
    
    var body: some View {
        
        NavigationStack {
            
            List(Array(searchCompleter.results.prefix(6)), id: \.self) { item in
                Button {
                    resolve(item)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .foregroundStyle(.primary)

                        if !item.subtitle.isEmpty {
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let userLocation {
                            DistanceView(completion: item, userLocation: userLocation)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Search location")
            .searchable(text: $query)
            .onChange(of: query) { _, newValue in
                searchCompleter.update(query: newValue)
            }
            .onAppear {
                guard userLocation == nil else { return }

                if locationManager.authorizationStatus == .notDetermined {
                    locationManager.requestWhenInUseAuthorization()
                }

                let delegate = LocationDelegate { location in
                    self.userLocation = location
                }

                locationManager.delegate = delegate
                self.locationDelegate = delegate

                locationManager.requestLocation()
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


final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    let onUpdate: (CLLocation) -> Void

    init(onUpdate: @escaping (CLLocation) -> Void) {
        self.onUpdate = onUpdate
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            onUpdate(loc)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // evita crash
    }
}


struct DistanceView: View {
    let completion: MKLocalSearchCompletion
    let userLocation: CLLocation

    @State private var distanceText: String = ""

    static var cache: [String: String] = [:]
    
    var body: some View {
        Text(distanceText)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .task(id: "\(completion.title)|\(completion.subtitle)") {
                await calculateDistance()
            }
    }

    private func calculateDistance() async {
        guard distanceText.isEmpty else { return }

        let key = "\(completion.title)|\(completion.subtitle)"

        if let cached = Self.cache[key] {
            distanceText = cached
            return
        }

        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)

        guard let response = try? await search.start(),
              let item = response.mapItems.first else { return }

        let location = item.location
        let distance = userLocation.distance(from: location)

        let text: String
        if distance < 1000 {
            text = "\(Int(distance)) m"
        } else {
            text = String(format: "%.1f km", distance / 1000)
        }

        // cache result
        Self.cache[key] = text

        await MainActor.run {
            distanceText = text
        }
    }
}
