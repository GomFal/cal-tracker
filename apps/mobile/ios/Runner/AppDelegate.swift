import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludePreferencesFromBackup()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func excludePreferencesFromBackup() {
    guard
      let libraryDirectory = FileManager.default.urls(
        for: .libraryDirectory,
        in: .userDomainMask
      ).first
    else {
      return
    }

    var preferencesDirectory = libraryDirectory.appendingPathComponent(
      "Preferences",
      isDirectory: true
    )
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    try? preferencesDirectory.setResourceValues(resourceValues)
  }
}
