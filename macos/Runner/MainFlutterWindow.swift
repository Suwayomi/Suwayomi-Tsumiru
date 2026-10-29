import Cocoa
import FlutterMacOS
import Sparkle
import window_manager

@MainActor
final class TsumiruSparkleUpdater {
  static let shared = TsumiruSparkleUpdater()

  private var controller: SPUStandardUpdaterController?

  func initialize() -> Bool {
    if controller != nil {
      return true
    }
    guard Self.isConfigured, !Self.hasMacAppStoreReceipt() else {
      return false
    }
    let controller = SPUStandardUpdaterController(
      startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    do {
      try controller.updater.start()
    } catch {
      NSLog("Tsumiru: Sparkle updater failed to start: %@", "\(error)")
      return false
    }
    self.controller = controller
    return true
  }

  // A running controller owns the request even while busy checking or
  // downloading; only a missing controller falls back to GitHub.
  func checkForUpdates() -> Bool {
    guard let updater = controller?.updater else {
      return false
    }
    if updater.canCheckForUpdates {
      updater.checkForUpdates()
    }
    return true
  }

  private static var isConfigured: Bool {
    guard let info = Bundle.main.infoDictionary,
      let feed = info["SUFeedURL"] as? String,
      let feedURL = URL(string: feed),
      feedURL.scheme?.lowercased() == "https",
      feedURL.host != nil,
      let key = info["SUPublicEDKey"] as? String,
      let keyData = Data(
        base64Encoded: key.trimmingCharacters(in: .whitespacesAndNewlines)),
      keyData.count == 32
    else {
      return false
    }
    return true
  }

  // Defensive: a real App Store target must drop the updater instead.
  private static func hasMacAppStoreReceipt() -> Bool {
    guard let receiptURL = Bundle.main.appStoreReceiptURL else {
      return false
    }
    return FileManager.default.fileExists(atPath: receiptURL.path)
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Draw our own theme-matching title bar in Flutter: hide the native one and
    // let content run full-height beneath the floating traffic lights.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let sparkleChannel = FlutterMethodChannel(
      name: "tsumiru/sparkle_updater",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    sparkleChannel.setMethodCallHandler { call, result in
      MainActor.assumeIsolated {
        switch call.method {
        case "initialize":
          result(TsumiruSparkleUpdater.shared.initialize())
        case "checkForUpdates":
          result(TsumiruSparkleUpdater.shared.checkForUpdates())
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    super.awakeFromNib()
  }

  override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}
