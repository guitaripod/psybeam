#if DEBUG
import MidgarUI
import UIKit

/// A tap-free pass over the screens a performance run measures, started by
/// `PSYBEAM_PERF_WALK=<dwell seconds>` in a DEBUG launch next to
/// `PSYBEAM_DEMO=perf`. It reports the frame watch stretch under each screen's
/// own name, dwells there long enough to read a steady state, scrolls a list
/// once, and moves on, so one run leaves a `Frame watch` line per screen.
extension ConversationViewController {
    func startPerfWalkIfNeeded() {
        guard let dwell = ProcessInfo.processInfo.environment["PSYBEAM_PERF_WALK"].flatMap(TimeInterval.init),
              dwell > 0, perfWalk == nil
        else { return }
        let walk = PerfWalk(dwell: dwell)
        perfWalk = walk
        walk.start(on: self)
    }
}

/// The timed sequence of ``PerfWalk``. Every step reports as it enters, so the
/// presentation animation is counted with the screen that shows it.
@MainActor
final class PerfWalk {
    private let dwell: TimeInterval
    private weak var host: ConversationViewController?

    init(dwell: TimeInterval) {
        self.dwell = dwell
    }

    func start(on host: ConversationViewController) {
        self.host = host
        let first = 1.0
        after(first) { [self] in enterConversation() }
        after(first + dwell) { [self] in enterConsent() }
        after(first + dwell * 2) { [self] in enterDestination() }
        after(first + dwell * 3) { [self] in enterSettings() }
        after(first + dwell * 4) { [self] in enterStore() }
        after(first + dwell * 5) { [self] in finish() }
    }

    private func enterConversation() {
        report("Conversation")
    }

    private func enterConsent() {
        guard let host else { return }
        report("Consent")
        host.presentConsent()
    }

    private func enterDestination() {
        guard let host else { return }
        host.dismiss(animated: true)
        after(0.6) { [self] in
            report("Destination")
            host.presentDestinationPicker()
            scrollList(of: host.presentedViewController, after: dwell * 0.6)
        }
    }

    private func enterSettings() {
        guard let host else { return }
        host.dismiss(animated: true)
        after(0.6) { [self] in
            report("Settings")
            host.openSettings()
            scrollList(of: host.presentedViewController, after: dwell * 0.6)
        }
    }

    private func enterStore() {
        guard let host else { return }
        host.dismiss(animated: true)
        after(0.7) { [self] in
            report("Credit store")
            host.presentStoreIfPossible()
            scrollList(of: host.presentedViewController, after: dwell * 0.6)
        }
    }

    private func finish() {
        report("Perf walk end")
        after(0.4) { [weak self] in self?.host?.dismiss(animated: true) }
    }

    private func report(_ screen: String) {
        MidgarFrameWatch.shared.report(screen)
    }

    private func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// One downward scroll of the sheet's list, far enough to re-lay a screenful
    /// and to show in the capture that the list itself was exercised.
    private func scrollList(of controller: UIViewController?, after delay: TimeInterval) {
        after(delay) {
            guard let scrollView = Self.firstScrollable(in: controller?.view),
                  scrollView.contentSize.height > scrollView.bounds.height
            else { return }
            let limit = scrollView.contentSize.height - scrollView.bounds.height
            let target = min(limit, scrollView.contentOffset.y + 260)
            scrollView.setContentOffset(CGPoint(x: 0, y: max(0, target)), animated: true)
        }
    }

    private static func firstScrollable(in view: UIView?) -> UIScrollView? {
        guard let view else { return nil }
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollable(in: subview) { return found }
        }
        return nil
    }
}
#endif
