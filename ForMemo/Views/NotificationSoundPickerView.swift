import SwiftUI
import AVFoundation
import AudioToolbox
import os

struct NotificationSoundPickerView: View {
    let context: SoundPickerContext
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedSound: String = ""
    
    @State private var sounds: [String] = []
    @State private var player: AVAudioPlayer?
    
    private var storageKey: String {
        context == .task ? "notificationSoundName" : "locationNotificationSoundName"
    }
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: Sezione Default
                Section {
                    HStack {
                        Text("Default")
                            .foregroundStyle(selectedSound.isEmpty ? .primary : .secondary)
                        
                        Spacer()
                        
                        if selectedSound.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSound = ""
                        UserDefaults.standard.set("", forKey: storageKey)
                        play(sound: "") // Riproduce il suono di sistema
                    }
                }
                
                // MARK: Sezione Custom
                Section("Custom Sounds") {
                    ForEach(sounds, id: \.self) { sound in
                        HStack {
                            Text(sound)
                                .foregroundStyle(selectedSound == sound ? .primary : .secondary)
                            
                            Spacer()
                            
                            if sound == selectedSound {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSound = sound
                            UserDefaults.standard.set(sound, forKey: storageKey)
                            play(sound: sound)
                        }
                    }
                }
            }
            
            .navigationTitle(context == .task ? "Notification sound" : "Location sound")
            .navigationBarTitleDisplayMode(.inline)
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
            .onAppear {
                loadSounds()
                selectedSound = UserDefaults.standard.string(forKey: storageKey) ?? ""
            }
        }
    }
    
    // MARK: - Logic
    
    private func loadSounds() {
        let extensions = ["wav", "mp3", "aiff", "caf"]
        var foundSounds: [String] = []
        
        for ext in extensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                foundSounds.append(contentsOf: urls.map { $0.lastPathComponent })
            }
        }
        sounds = foundSounds.sorted()
    }
    
    private func play(sound: String) {
        // Ferma sempre il player prima di iniziare una nuova riproduzione
        player?.stop()
        
        if sound.isEmpty {
            // Riproduce il suono di notifica standard di iOS (ID 1312)
            // Documentazione ufficiale: https://developer.apple.com
            AudioServicesPlaySystemSound(1312)
            return
        }
        
        guard let url = Bundle.main.url(forResource: sound, withExtension: nil) else { return }
        
        do {
            // Configura la sessione per riprodurre audio anche se il telefono è in modalità silenziosa (opzionale)
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()
        } catch {
            
            AppLogger.app.error("Errore Audio: \(error.localizedDescription)")
        }
    }
    
    
}
