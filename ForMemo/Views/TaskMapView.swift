struct TaskMapAnnotationModel: Identifiable, Equatable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    
    let title: String
    let tagIcon: String?
    let deadline: Date?
    let address: String?
    let locationName: String?
    
    let isUrgent: Bool

    static func == (lhs: TaskMapAnnotationModel, rhs: TaskMapAnnotationModel) -> Bool {
        lhs.id == rhs.id &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.title == rhs.title &&
        lhs.tagIcon == rhs.tagIcon &&
        lhs.deadline == rhs.deadline &&
        lhs.address == rhs.address &&
        lhs.locationName == rhs.locationName &&
        lhs.isUrgent == rhs.isUrgent
    }
}

import SwiftUI
import MapKit
import SwiftData

struct TaskMapView: View {
    
    @Environment(\.modelContext) private var context
    
    @Query(filter: #Predicate<TodoTask> { !$0.isCompleted })
    private var tasks: [TodoTask]
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.9028, longitude: 12.4964), // Roma default
        span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
    )
    
    @State private var zoomLevel: Double = 0.2
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    
    @State private var selectedTask: TodoTask?
    @State private var hasSetInitialRegion = false
    
var body: some View {
    
    NavigationStack {
        Map(position: $cameraPosition) {
            mapAnnotations
        }
        .onMapCameraChange { context in
            zoomLevel = context.region.span.latitudeDelta
        }
        .ignoresSafeArea()
        .task {
            guard !hasSetInitialRegion else { return }
            if let region = boundingRegion {
                cameraPosition = .region(region)
                hasSetInitialRegion = true
            }
        }
        .onChange(of: mapModels.map(\.id)) { _, _ in
            guard !mapModels.isEmpty else { return }
            guard !hasSetInitialRegion else { return }
            
            if let region = boundingRegion {
                withAnimation(.easeInOut(duration: 0.5)) {
                    cameraPosition = .region(region)
                    hasSetInitialRegion = true
                }
            }
        }
        .navigationDestination(item: $selectedTask) { task in
            TaskDetailView(task: task)
        }
    }
}
}


extension TaskMapView {
    
    var mapModels: [TaskMapAnnotationModel] {
        
        tasks.compactMap { task -> TaskMapAnnotationModel? in
            
            guard let lat = task.locationLatitude,
                  let lon = task.locationLongitude else { return nil }
            
            let isUrgent = {
                guard let d = task.deadLine else { return false }
                return d.timeIntervalSinceNow < 86400 && d.timeIntervalSinceNow > 0
            }()
            
            return TaskMapAnnotationModel(
                id: task.id,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                title: task.title,
                tagIcon: nil,
                deadline: task.deadLine,
                address: nil,
                locationName: task.locationName,
                isUrgent: isUrgent
            )
        }
    }
    
    var boundingRegion: MKCoordinateRegion? {
        guard !mapModels.isEmpty else { return nil }
        
        let lats = mapModels.map { $0.coordinate.latitude }
        let lons = mapModels.map { $0.coordinate.longitude }
        
        guard let minLat = lats.min(),
              let maxLat = lats.max(),
              let minLon = lons.min(),
              let maxLon = lons.max() else { return nil }
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.01, (maxLon - minLon) * 1.4)
        )
        
        return MKCoordinateRegion(center: center, span: span)
    }
    
    var mapAnnotations: some MapContent {
        ForEach(mapModels) { item in
            Annotation("", coordinate: item.coordinate) {
                annotationButton(for: item)
            }
        }
    }

    private func annotationButton(for item: TaskMapAnnotationModel) -> some View {
        Button {
            if let task = tasks.first(where: { $0.id == item.id }) {
                selectedTask = task
            }
        } label: {
            TaskAnnotationView(
                model: item,
                zoomLevel: zoomLevel
            )
        }
        .buttonStyle(.plain)
    }
}

struct TaskAnnotationView: View {
    
    let model: TaskMapAnnotationModel
    let zoomLevel: Double
    
    @State private var blink = false
    
    var body: some View {
        
        VStack(spacing: 4) {
            
            // 🔴 BASE DOT + RADAR PULSE
            ZStack {
                // 🔴 BASE DOT
                Circle()
                    .fill(model.isUrgent ? Color.red : Color.blue)
                    .shadow(color: model.isUrgent ? Color.red.opacity(0.9) : Color.blue.opacity(0.6), radius: 4)
                    .frame(width: 12, height: 12)
                
                // 🔥 RADAR PULSE 1
                if model.isUrgent && zoomLevel < 0.08 {
                    Circle()
                        .stroke(Color.red, lineWidth: 3)
                        .frame(width: 12, height: 12)
                        .scaleEffect(blink ? 3.5 : 1.0)
                        .opacity(blink ? 0.0 : 1.0)
                        .animation(
                            .easeOut(duration: 1.2)
                            .repeatForever(autoreverses: false),
                            value: blink
                        )
                }
                
                // 🔥 RADAR PULSE 2 (offset for continuous effect)
                if model.isUrgent && zoomLevel < 0.08 {
                    Circle()
                        .stroke(Color.red.opacity(0.9), lineWidth: 2)
                        .frame(width: 12, height: 12)
                        .scaleEffect(blink ? 3.5 : 1.0)
                        .opacity(blink ? 0.0 : 0.9)
                        .animation(
                            .easeOut(duration: 1.2)
                            .repeatForever(autoreverses: false)
                            .delay(0.4),
                            value: blink
                        )
                }
            }
            
            // 🔍 DETTAGLIO SOLO SE ZOOM
            if zoomLevel < 0.05 {
                detailView
                    .transition(.opacity)
            }
        }
        .onAppear {
            if model.isUrgent && zoomLevel < 0.08 {
                // 🔥 trigger continuous animation
                withAnimation {
                    blink.toggle()
                }
            }
        }
        .onChange(of: zoomLevel) { _, newValue in
            if model.isUrgent && newValue < 0.08 {
                withAnimation {
                    blink = false
                    blink.toggle()
                }
            }
        }
    }
}

extension TaskAnnotationView {
    
    var detailView: some View {
        
        VStack(alignment: .leading, spacing: 4) {
            
            HStack(spacing: 6) {
                
                if let icon = model.tagIcon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                
                Text(model.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            
            if let deadline = model.deadline {
                Text(deadline.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            if let locationName = model.locationName {
                Text(locationName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            if let address = model.address {
                Text(address)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 2)
    }
}
