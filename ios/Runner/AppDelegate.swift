import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

/// Root view controller cho game ngang (khai báo trong Main.storyboard).
/// - Ẩn status bar.
/// - Mép dưới phải vuốt 2 lần mới về màn hình chính: ngón cái đang giữ cần
///   lái / cụm nút sát mép dưới rất dễ quẹt trúng cử chỉ Home.
class GameViewController: FlutterViewController {
  override var prefersStatusBarHidden: Bool { true }

  override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .bottom }
}
