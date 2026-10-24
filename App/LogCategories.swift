import MidgarCore

nonisolated extension MidgarLog.Category {
    static let app = MidgarLog.Category("app")
    static let auth = MidgarLog.Category("auth")
    static let session = MidgarLog.Category("session")
    static let webrtc = MidgarLog.Category("webrtc")
    static let audio = MidgarLog.Category("audio")
    static let location = MidgarLog.Category("location")
    static let translate = MidgarLog.Category("translate")
    static let persistence = MidgarLog.Category("persistence")
    static let review = MidgarLog.Category("review")
}
