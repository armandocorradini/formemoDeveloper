import SwiftUI
import AVFoundation

struct AudioPlayerRow: View {
    
    let url: URL
    
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    
    var body: some View {
        
        Button {
            toggle()
        } label: {
            
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .font(.title3)
        }
        .buttonStyle(.plain)
        .onDisappear {
            stop()
        }
    }
    
    private func toggle() {
        
        if isPlaying {
            stop()
            return
        }
        
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
            isPlaying = true
        } catch {
            stop()
        }
    }
    
    private func stop() {
        
        player?.stop()
        player = nil
        isPlaying = false
    }
}
