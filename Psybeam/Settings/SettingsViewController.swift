import AVFoundation
import Combine
import MidgarPortal
import MidgarUI
import UIKit

/// The Settings sheet: MidgarUI's settings list with Psybeam's sections, inside a navigation controller so a language
/// row can push its picker. The list is rebuilt whenever something it shows changes: the minutes balance, either
/// language and the microphone mode.
final class SettingsViewController: UINavigationController {
    let viewModel: ConversationViewModel
    let onBrightnessChanged: () -> Void
    let onAutoDetectEnabled: () -> Void
    var onDismiss: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private var micModeTask: Task<Void, Never>?
    private var shownMicMode = SettingsViewController.currentMicModeName()

    private lazy var list = MidgarSettingsViewController(
        title: String(localized: "Settings"),
        sections: makeSections(),
        portalCardView: MidgarEntryView(config: PsybeamMidgar.shared.portalConfig),
        theme: .psybeam
    )

    init(
        viewModel: ConversationViewModel,
        onBrightnessChanged: @escaping () -> Void,
        onAutoDetectEnabled: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onBrightnessChanged = onBrightnessChanged
        self.onAutoDetectEnabled = onAutoDetectEnabled
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.tintColor = MidgarTheme.psybeam.uiAccent
        navigationBar.prefersLargeTitles = true
        list.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        viewControllers = [list]
        observeBalance()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshList()
        Task { await AICreditsManager.store.refresh() }
        watchMicMode()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        micModeTask?.cancel()
        micModeTask = nil
        if presentingViewController == nil || isBeingDismissed { onDismiss?() }
    }

    /// Rebuilds every row from the current state. Rows read their values when built, so a change is shown by building
    /// them again.
    func refreshList() {
        shownMicMode = Self.currentMicModeName()
        list.sections = makeSections()
    }

    /// Keep the minutes row live: the credit store sheet (and in-session billing) mutate the shared store's balance
    /// while this screen stays presented, and dismissing a sheet doesn't re-fire `viewDidAppear` on the presenter, so
    /// the list follows the published balance instead of only sampling it on appear.
    private func observeBalance() {
        guard !isDemoLaunch else { return }
        AICreditsManager.store.$balance
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshList() }
            .store(in: &cancellables)
    }

    /// iOS offers no notification for the microphone mode, which the person changes in Control Center, so it is read
    /// once a second while the sheet is open and the list is rebuilt only when it changed.
    private func watchMicMode() {
        micModeTask?.cancel()
        micModeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if Self.currentMicModeName() != shownMicMode { refreshList() }
            }
        }
    }

    static func currentMicModeName() -> String {
        switch AVCaptureDevice.activeMicrophoneMode {
        case .voiceIsolation: String(localized: "Voice Isolation")
        case .wideSpectrum: String(localized: "Wide Spectrum")
        case .standard: String(localized: "Standard")
        @unknown default: String(localized: "Standard")
        }
    }

    /// A demo launch shows the documented free-tier grant instead of the live balance: simulators can never pass the
    /// App Attest check mako's identity endpoint requires, so the real balance is always stuck at 0 there, which would
    /// misrepresent what a real first launch shows.
    var isDemoLaunch: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["PSYBEAM_DEMO"] != nil
        #else
        false
        #endif
    }
}
