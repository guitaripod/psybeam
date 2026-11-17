import MidgarCore
import PsybeamCore
import SwiftUI
import UIKit

extension ConversationViewController {
    var features: ModelFeatureVisibility {
        .current
    }

    func bindModelRegion() {
        NotificationCenter.default.publisher(for: MidgarModelRegion.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.modelRegionChanged() }
            .store(in: &cancellables)
    }

    /// Follows Midgar's answer the moment it flips. Where model features are refused, the warm legs hang up, the sheets
    /// that teach or sell them close and the caption says the region line; where they work again, a warm-up resumes.
    func modelRegionChanged() {
        if features.showsRegionLine {
            dismissModelSheets()
            viewModel.end()
            abandonPendingTurns()
        } else if AppSettings.aiConsentGranted, sessionStarted {
            warmUpIfMicGranted()
        }
        refreshNotice()
        refreshResting()
    }

    /// Consent, the destination picker and the credit store are the sheets that present a model feature.
    private func dismissModelSheets() {
        guard let presented = presentedViewController else { return }
        let presentsModelFeature = presented is ConsentViewController
            || presented is DestinationPickerViewController
            || presented is UIHostingController<CreditStoreSheet>
        if presentsModelFeature {
            dismiss(animated: true)
        }
    }
}
