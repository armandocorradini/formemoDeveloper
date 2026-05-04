enum UrgencyLevel {
    case none, soon, overdue
}

struct TaskMapAnnotationModel: Identifiable, Equatable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    
    let title: String
    let tagIcon: String?
    let deadline: Date?
    let address: String?
    let locationName: String?
    
    let urgency: UrgencyLevel
    let items: [Item]

    struct Item: Identifiable, Equatable {
        let id: UUID
        let title: String
        let deadline: Date?
        let urgency: UrgencyLevel
        let tagIcon: String?
    }

    static func == (lhs: TaskMapAnnotationModel, rhs: TaskMapAnnotationModel) -> Bool {
        lhs.id == rhs.id &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.title == rhs.title &&
        lhs.tagIcon == rhs.tagIcon &&
        lhs.deadline == rhs.deadline &&
        lhs.address == rhs.address &&
        lhs.locationName == rhs.locationName &&
        lhs.urgency == rhs.urgency &&
        lhs.items == rhs.items
    }
}

import SwiftUI
import MapKit
import SwiftData

struct ZoomStore {
    static var zoomLevel: Double = 0.2
    static var latDelta: Double = 0.2
    static var lonDelta: Double = 0.2
    static var centerLat: Double = 41.9028
    static var centerLon: Double = 12.4964
}

struct TaskMapView: View {
    
    @Environment(\.modelContext) private var context
    
    @Query(filter: #Predicate<TodoTask> { !$0.isCompleted })
    private var tasks: [TodoTask]
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.9028, longitude: 12.4964), // Roma default
        span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
    )
    
    @State private var zoomLevel: Double = ZoomStore.zoomLevel
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var storedLatDelta: Double = ZoomStore.latDelta
    @State private var storedLonDelta: Double = ZoomStore.lonDelta
    @State private var storedCenterLat: Double = ZoomStore.centerLat
    @State private var storedCenterLon: Double = ZoomStore.centerLon
    
    @Environment(\.scenePhase) private var scenePhase
    @State private var didInitializeLaunch = false
    @State private var hasSetInitialRegion = false

    @Binding var mapPath: NavigationPath

    var body: some View {
        Map(position: $cameraPosition) {
            mapAnnotations
        }
        .onMapCameraChange { context in
            zoomLevel = context.region.span.latitudeDelta
            storedLatDelta = context.region.span.latitudeDelta
            storedLonDelta = context.region.span.longitudeDelta
            storedCenterLat = context.region.center.latitude
            storedCenterLon = context.region.center.longitude
            ZoomStore.zoomLevel = zoomLevel
            ZoomStore.latDelta = storedLatDelta
            ZoomStore.lonDelta = storedLonDelta
            ZoomStore.centerLat = storedCenterLat
            ZoomStore.centerLon = storedCenterLon
        }
        .ignoresSafeArea()
        .task {
            guard !hasSetInitialRegion else { return }

            // If we already have a stored zoom, restore ONLY that and skip bounding region
            if storedLatDelta != 0.2 {
                let restoredRegion = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: storedCenterLat, longitude: storedCenterLon),
                    span: MKCoordinateSpan(latitudeDelta: storedLatDelta, longitudeDelta: storedLonDelta)
                )
                cameraPosition = .region(restoredRegion)
                hasSetInitialRegion = true
                return
            }

            // First launch: fit all annotations
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
        .navigationDestination(for: TodoTask.self) { task in
            TaskDetailView(task: task)
        }
    }
}


extension TaskMapView {
    
    var mapModels: [TaskMapAnnotationModel] {
        let grouped = Dictionary(grouping: tasks.compactMap { task -> (CLLocationCoordinate2D, TaskMapAnnotationModel.Item)? in
            guard let lat = task.locationLatitude,
                  let lon = task.locationLongitude else { return nil }

            let urgency: UrgencyLevel = {
                guard let d = task.deadLine else { return .none }
                let interval = d.timeIntervalSinceNow
                if interval < 0 { return .overdue }
                if interval < 86400 { return .soon }
                return .none
            }()

            let item = TaskMapAnnotationModel.Item(
                id: task.id,
                title: task.title,
                deadline: task.deadLine,
                urgency: urgency,
                tagIcon: task.mainTag?.mainIcon
            )

            return (CLLocationCoordinate2D(latitude: lat, longitude: lon), item)
        }) { pair in
            // group key by exact coordinate
            "\(pair.0.latitude)-\(pair.0.longitude)"
        }

        return grouped.map { _, pairs in
            // extract coordinate and items
            let coordinate = pairs.first!.0
            var items = pairs.map { $0.1 }

            // sort by deadline ascending (nil last)
            items.sort { a, b in
                switch (a.deadline, b.deadline) {
                case let (da?, db?): return da < db
                case (nil, _?): return false
                case (_?, nil): return true
                default: return a.title < b.title
                }
            }

            // highest urgency for dot
            let urgency = items.map { $0.urgency }.max { a, b in
                func p(_ u: UrgencyLevel) -> Int {
                    switch u {
                    case .overdue: return 2
                    case .soon: return 1
                    case .none: return 0
                    }
                }
                return p(a) < p(b)
            } ?? .none

            // pick most urgent item for tag icon
            let mostUrgentItem = items.max { a, b in
                func p(_ u: UrgencyLevel) -> Int {
                    switch u {
                    case .overdue: return 2
                    case .soon: return 1
                    case .none: return 0
                    }
                }
                return p(a.urgency) < p(b.urgency)
            }

            let tagIcon = tasks.first(where: { $0.id == mostUrgentItem?.id })?.mainTag?.mainIcon

            return TaskMapAnnotationModel(
                id: items.first!.id,
                coordinate: coordinate,
                title: "", // no longer used for multi-line label
                tagIcon: tagIcon,
                deadline: nil,
                address: nil,
                locationName: tasks.first(where: { $0.locationLatitude == coordinate.latitude && $0.locationLongitude == coordinate.longitude })?.locationName,
                urgency: urgency,
                items: items
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
        ForEach(mapModels.sorted { lhs, rhs in
            // higher priority first (drawn later = on top)
            func priority(_ u: UrgencyLevel) -> Int {
                switch u {
                case .overdue: return 2
                case .soon: return 1
                case .none: return 0
                }
            }
            return priority(lhs.urgency) < priority(rhs.urgency)
        }) { item in
            Annotation("", coordinate: item.coordinate) {
                annotationButton(for: item)
            }
        }
    }

    private func annotationButton(for item: TaskMapAnnotationModel) -> some View {
        Button {
            if let task = tasks.first(where: { $0.id == item.id }) {
                mapPath.append(task)
            }
        } label: {
            TaskAnnotationView(
                model: item,
                zoomLevel: zoomLevel,
                onSelectTask: { id in
                    if let task = tasks.first(where: { $0.id == id }) {
                        mapPath.append(task)
                    }
                }
            )
            .offset(
                x: CGFloat((item.id.uuidString.hashValue % 10) - 5),
                y: CGFloat((item.id.uuidString.hashValue % 10) - 5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct TaskAnnotationView: View {
    
    let model: TaskMapAnnotationModel
    let zoomLevel: Double
    let onSelectTask: (UUID) -> Void
    
    @State private var blink = false
    
    var body: some View {
        
        VStack(spacing: 4) {
            // 🔴 BASE DOT + RADAR PULSE (NO TAG ICON)
            ZStack {
                // 🔴 BASE DOT
                Circle()
                    .fill({
                        switch model.urgency {
                        case .overdue: return Color(red: 1.0, green: 0.1, blue: 0.1)
                        case .soon: return Color(red: 0.7, green: 0.0, blue: 0.9)
                        case .none: return Color.indigo
                        }
                    }())
                    .shadow(color: ({
                        switch model.urgency {
                        case .overdue: return Color(red: 1.0, green: 0.1, blue: 0.1).opacity(0.9)
                        case .soon: return Color(red: 0.7, green: 0.0, blue: 0.9).opacity(0.9)
                        case .none: return Color.indigo.opacity(0.6)
                        }
                    }()), radius: 4)
                    .frame(width: 12, height: 12)

                // 🔥 RADAR PULSE 1
                if model.urgency != .none && zoomLevel < 0.08 {
                    Circle()
                        .stroke(({
                            switch model.urgency {
                            case .overdue: return Color(red: 1.0, green: 0.1, blue: 0.1)
                            case .soon: return Color(red: 0.7, green: 0.0, blue: 0.9)
                            case .none: return Color.clear
                            }
                        }()), lineWidth: 3)
                        .frame(width: 12, height: 12)
                        .scaleEffect(blink ? 3.5 : 1.0)
                        .opacity(blink ? 0.0 : 1.0)
                        .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: blink)
                }

                // 🔥 RADAR PULSE 2
                if model.urgency != .none && zoomLevel < 0.08 {
                    Circle()
                        .stroke(({
                            switch model.urgency {
                            case .overdue: return Color(red: 1.0, green: 0.1, blue: 0.1).opacity(0.9)
                            case .soon: return Color(red: 0.7, green: 0.0, blue: 0.9).opacity(0.9)
                            case .none: return Color.clear
                            }
                        }()), lineWidth: 2)
                        .frame(width: 12, height: 12)
                        .scaleEffect(blink ? 3.5 : 1.0)
                        .opacity(blink ? 0.0 : 0.9)
                        .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false).delay(0.4), value: blink)
                }
            }

            // 🔍 DETTAGLIO SOLO SE ZOOM
            if zoomLevel < 0.05 {
                detailView
                    .transition(.opacity)
            }
        }
        .onAppear {
            if model.urgency != .none && zoomLevel < 0.08 {
                // 🔥 trigger continuous animation
                withAnimation {
                    blink.toggle()
                }
            }
        }
        .onChange(of: zoomLevel) { _, newValue in
            if model.urgency != .none && newValue < 0.08 {
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
            ForEach(model.items) { it in
                Button {
                    onSelectTask(it.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            if let icon = it.tagIcon {
                                Image(systemName: icon)
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                            }

                            Circle()
                                .fill({
                                    switch it.urgency {
                                    case .overdue: return Color(red: 1.0, green: 0.1, blue: 0.1)
                                    case .soon: return Color(red: 0.7, green: 0.0, blue: 0.9)
                                    case .none: return Color.indigo
                                    }
                                }())
                                .frame(width: 6, height: 6)

                            Text(it.title)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                        }

                        if let d = it.deadline {
                            Text(d.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 12)
                        }
                    }
                }
                .buttonStyle(.plain)
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
