import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

actor ImageCache {
    static let shared = ImageCache()
    
    private var cache: [URL: UIImage] = [:]
    
    func image(for url: URL) -> UIImage? {
        cache[url]
    }
    
    func set(_ image: UIImage, for url: URL) {
        cache[url] = image
    }
}

struct AttachmentRow: View {
    
    let attachment: TaskAttachment
    let onDelete: (() -> Void)?
    
    enum LoadState: Equatable {
        case idle
        case loading
        case success(UIImage)
        case failed
        case downloading
    }
    
    @State private var state: LoadState = .idle
    
    var body: some View {
        
        HStack(spacing: 12) {
            
            leadingPreview
            
            Text(attachment.shortDisplayName)
                .lineLimit(1)
            
            Spacer()
            
            trailingControls
        }
        .contentShape(Rectangle())
        
        // LOAD iniziale
        .task {
            await loadIfNeeded()
        }
        
        // RETRY manuale
        .onTapGesture {
            if case .failed = state {
                retry()
            }
        }
        
        // CAMBIO file locale
        .onChange(of: attachment.relativePath) { _, _ in
            retry()
        }
        
        
        
        .animation(.easeInOut(duration: 0.2), value: state)
    }
    
    // MARK: - Leading Preview
    
    @ViewBuilder
    private var leadingPreview: some View {
        
        if isAudio {
            
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)
            
        } else if isImage {
            
            ZStack {
                
                switch state {
                    
                case .success(let image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                case .loading:
                    ProgressView()
                        .frame(width: 36, height: 36)
                    
                case .downloading:
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .symbolEffect(.pulse)
                        .frame(width: 36, height: 36)
                    
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .frame(width: 36, height: 36)
                    
                case .idle:
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
            }
            
        } else {
            
            Image(systemName: systemIcon)
                .font(.title3)
                .frame(width: 36, height: 36)
        }
    }
    
    // MARK: - Trailing
    
    @ViewBuilder
    private var trailingControls: some View {
        
        HStack(spacing: 12) {
            
            if isAudio,
               let url = attachment.fileURL {
                AudioPlayerRow(url: url)
            }
            
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "x.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - LOAD CORE
    
    private func loadIfNeeded() async {
        
        guard case .idle = state else { return }
        guard isImage else { return }
        
        await loadImage()
    }
    
    private func retry() {
        state = .idle
        
        Task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        
        guard let url = attachment.fileURL else {
            state = .failed
            return
        }
        
        let fm = FileManager.default
        
        // 🔥 1. CACHE (subito)
        if let cached = await ImageCache.shared.image(for: url) {
            state = .success(cached)
            return
        }
        
        // ❌ file non esiste
        guard fm.fileExists(atPath: url.path) else {
            print("❌ FILE NOT FOUND:", url.lastPathComponent)
            state = .failed
            return
        }
        
        // 🔹 iCloud check
        var isUbiquitous: AnyObject?
        try? (url as NSURL).getResourceValue(
            &isUbiquitous,
            forKey: .isUbiquitousItemKey
        )
        
        let isCloud = (isUbiquitous as? Bool) == true
        
        if isCloud {
            state = .downloading
            try? fm.startDownloadingUbiquitousItem(at: url)
        } else {
            state = .loading
        }
        
        // 🔥 2. RETRY (pulito e stabile)
        for attempt in 0..<6 {
            
            // 🔥 ricontrollo cache (può arrivare da altri thread)
            if let cached = await ImageCache.shared.image(for: url) {
                state = .success(cached)
                return
            }
            
            // 🔥 load da disco
            if let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                
                await ImageCache.shared.set(image, for: url)
                state = .success(image)
                return
            }
            
            // 🔹 attesa progressiva (più elegante)
            let delay = UInt64(300_000_000 + (attempt * 100_000_000))
            try? await Task.sleep(nanoseconds: delay)
        }
        
        print("❌ LOAD FAILED:", attachment.originalName)
        state = .failed
    }
    
    // MARK: - Type
    
    private var resolvedType: UTType? {
        UTType(mimeType: attachment.contentType)
        ?? UTType(attachment.contentType)
    }
    
    private var isImage: Bool {
        resolvedType?.conforms(to: .image) ?? false
    }
    
    private var isAudio: Bool {
        resolvedType?.conforms(to: .audio) ?? false
    }
    
    private var systemIcon: String {
        
        guard let type = resolvedType else { return "doc" }
        
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .movie) { return "film" }
        if type.conforms(to: .image) { return "photo" }
        
        return "doc"
    }
}
