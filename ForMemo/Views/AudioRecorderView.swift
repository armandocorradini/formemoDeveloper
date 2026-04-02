import SwiftUI
import AVFoundation

struct AudioRecorderView: View {
    
    @Environment(\.dismiss)
    private var dismiss
    
    let onSave: (URL) -> Void
    
    @State private var recorder: AVAudioRecorder?
    @State private var isRecording = false
    @State private var recordedURL: URL?
    
    private var tempURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Voice-\(UUID().uuidString).m4a")
    }
    
    var body: some View {
        
        NavigationStack {
            
            VStack(spacing: 32) {
                
                Image(systemName: isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 64))
                    .foregroundStyle(isRecording ? .red : .primary)
                
                if isRecording {
                    Text("Recording…")
                        .foregroundStyle(.secondary)
                } else if recordedURL != nil {
                    Text("Ready to save")
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 32) {
                    
                    Button {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    } label: {
                        Label(
                            isRecording ? "Stop" : "Record",
                            systemImage: isRecording ? "stop.circle.fill" : "record.circle"
                        )
                        .font(.title2)
                    }
                    
                    if let recordedURL {
                        
                        Button {
                            onSave(recordedURL)
                            dismiss()
                        } label: {
                            Label("Save", systemImage: "checkmark.circle.fill")
                                .font(.title2)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Voice note")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await requestPermission()
            }
        }
    }
    
    // MARK: - Recording
    
    private func requestPermission() async {
        
        _ = await AVAudioApplication.requestRecordPermission()
    }
    
    private func startRecording() {
        
        let session = AVAudioSession.sharedInstance()
        
        try? session.setCategory(.playAndRecord, mode: .default)
        try? session.setActive(true)
        
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        let recorder = try? AVAudioRecorder(
            url: tempURL,
            settings: settings
        )
        
        recorder?.record()
        
        self.recorder = recorder
        isRecording = true
        recordedURL = nil
    }
    
    private func stopRecording() {
        
        recorder?.stop()
        recordedURL = recorder?.url
        recorder = nil
        isRecording = false
    }
}
