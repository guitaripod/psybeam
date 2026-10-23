import AVFAudio
import MidgarCore
import UIKit

extension ConversationViewController {
    /// Asked from the user's own first hold, so the system dialog is the direct
    /// result of what they just did and the coach line has already said why.
    func requestMicPermission() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in self?.micPermissionAnswered(granted: granted) }
        }
    }

    func micPermissionAnswered(granted: Bool) {
        MidgarLog.info("microphone permission \(granted ? "granted" : "denied")", category: .ui)
        guard granted else {
            render(legState: .permissionDenied(.microphone), speaker: .traveler)
            return
        }
        micDenied = false
        refreshResting()
        warmUpIfMicGranted()
    }

    @objc func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Back from Settings, the screen follows whatever the switch now says.
    func recheckMicPermission() {
        guard sessionStarted else { return }
        let denied = AVAudioApplication.shared.recordPermission == .denied
        guard denied != micDenied else { return }
        micDenied = denied
        if !denied { render(legState: .idle, speaker: .traveler) }
        refreshResting()
    }
}
