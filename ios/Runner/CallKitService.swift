import CallKit
import AVFoundation

class CallKitService: NSObject, CXProviderDelegate {

    static let shared = CallKitService()

    private let provider: CXProvider
    private let callController = CXCallController()
    private var currentCallUUID: UUID?

    override init() {
        let config = CXProviderConfiguration()
        config.localizedName = "XamePage"
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        if let icon = UIImage(named: "AppIcon") {
            config.iconTemplateImageData = icon.pngData()
        }
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    func reportIncomingCall(callerName: String, callType: String) {
        let uuid = UUID()
        currentCallUUID = uuid
        let handle = CXHandle(type: .generic, value: callerName)
        let update = CXCallUpdate()
        update.remoteHandle = handle
        update.hasVideo = callType == "video"
        update.localizedCallerName = callerName
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error = error {
                print("[CallKit] Error reporting incoming call: \(error)")
            }
        }
    }

    func endCall() {
        guard let uuid = currentCallUUID else { return }
        let action = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: action)
        callController.request(transaction) { error in
            if let error = error {
                print("[CallKit] Error ending call: \(error)")
            }
        }
        currentCallUUID = nil
    }

    // MARK: - CXProviderDelegate
    func providerDidReset(_ provider: CXProvider) {
        currentCallUUID = nil
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        // Notify Flutter to answer the call
        NotificationCenter.default.post(name: Notification.Name("CallAnswered"), object: nil)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        // Notify Flutter to end the call
        NotificationCenter.default.post(name: Notification.Name("CallEnded"), object: nil)
        currentCallUUID = nil
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        try? audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
        try? audioSession.setActive(true)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        try? audioSession.setActive(false)
    }
}
