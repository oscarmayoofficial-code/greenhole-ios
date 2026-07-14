import AVFoundation
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MutePlugin") {
      MutePlugin.register(with: registrar)
    }
  }
}

/// Native implementation of the app's visible "remove sound" feature.
///
/// Builds an AVMutableComposition that contains only the video track of the
/// source asset (the audio track is simply never inserted), then exports it to
/// a fresh .mp4 in the temp directory and returns that path to Dart.
///
/// Defined here (not in a separate file) so it compiles without editing the
/// Xcode project on a machine that has no Xcode.
///
/// MethodChannel: `com.oscar.greenhole/mute`  ·  method: `removeAudio`
class MutePlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.oscar.greenhole/mute",
      binaryMessenger: registrar.messenger())
    let instance = MutePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "removeAudio" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let args = call.arguments as? [String: Any],
      let input = args["input"] as? String
    else {
      result(FlutterError(code: "bad_args", message: "Missing input path", details: nil))
      return
    }
    removeAudio(inputPath: input, result: result)
  }

  private func removeAudio(inputPath: String, result: @escaping FlutterResult) {
    let srcURL = URL(fileURLWithPath: inputPath)
    let asset = AVURLAsset(url: srcURL)

    let composition = AVMutableComposition()
    guard
      let videoTrack = asset.tracks(withMediaType: .video).first,
      let compVideoTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid)
    else {
      result(FlutterError(code: "no_video", message: "No video track found.", details: nil))
      return
    }

    do {
      let range = CMTimeRange(start: .zero, duration: asset.duration)
      try compVideoTrack.insertTimeRange(range, of: videoTrack, at: .zero)
      // Preserve orientation from the source track.
      compVideoTrack.preferredTransform = videoTrack.preferredTransform
    } catch {
      result(FlutterError(code: "compose_failed", message: error.localizedDescription, details: nil))
      return
    }

    let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("muted_\(Int(Date().timeIntervalSince1970 * 1000)).mp4")
    try? FileManager.default.removeItem(at: outURL)

    guard
      let export = AVAssetExportSession(
        asset: composition, presetName: AVAssetExportPresetHighestQuality)
    else {
      result(FlutterError(code: "no_export", message: "Could not create exporter.", details: nil))
      return
    }
    export.outputURL = outURL
    export.outputFileType = .mp4
    export.shouldOptimizeForNetworkUse = true

    export.exportAsynchronously {
      DispatchQueue.main.async {
        switch export.status {
        case .completed:
          result(outURL.path)
        case .failed, .cancelled:
          result(FlutterError(
            code: "export_failed",
            message: export.error?.localizedDescription ?? "Export failed.",
            details: nil))
        default:
          result(FlutterError(code: "export_failed", message: "Unexpected export state.", details: nil))
        }
      }
    }
  }
}
