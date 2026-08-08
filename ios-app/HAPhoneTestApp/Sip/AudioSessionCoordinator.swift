import AVFoundation

/// Owns AVAudioSession configuration -- ONLY ever called from
/// CXProviderDelegate's didActivate/didDeactivate (RESEARCH.md Pattern 2:
/// configuring the session outside those callbacks causes audio-session
/// ownership conflicts with CallKit).
enum AudioSessionCoordinator {
    static func activate(_ audioSession: AVAudioSession) {
        try? audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
    }

    static func deactivate(_ audioSession: AVAudioSession) {
        try? audioSession.setActive(false)
    }
}
