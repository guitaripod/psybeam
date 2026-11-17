import MidgarCore
import PsybeamCore

extension ModelFeatureVisibility {
    /// What the screens show right now, from the device's last answer on whether model features work here.
    static var current: ModelFeatureVisibility {
        ModelFeatureVisibility(modelsAvailable: MidgarModelRegion.shared.modelsAvailable)
    }
}
