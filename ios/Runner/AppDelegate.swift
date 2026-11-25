import Flutter
import UIKit
import VisionKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  VNDocumentCameraViewControllerDelegate {
  private var importChannel: FlutterMethodChannel?
  private var pendingPdfs: [String] = []
  private var scanResult: FlutterResult?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "encoresheets/import",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    importChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "take" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let paths = self?.pendingPdfs ?? []
      self?.pendingPdfs.removeAll()
      result(paths)
    }
    let scanner = FlutterMethodChannel(
      name: "encoresheets/scanner",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    scanner.setMethodCallHandler { [weak self] call, result in
      guard call.method == "scan", let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.startScan(result)
    }
  }

  private func startScan(_ result: @escaping FlutterResult) {
    guard VNDocumentCameraViewController.isSupported, scanResult == nil,
          var presenter = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "scan_unavailable",
                          message: "The document scanner is unavailable.", details: nil))
      return
    }
    while let next = presenter.presentedViewController { presenter = next }
    let scanner = VNDocumentCameraViewController()
    scanner.delegate = self
    scanResult = result
    presenter.present(scanner, animated: true)
  }

  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    completeScan(controller, value: nil)
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController, didFailWithError error: Error
  ) {
    completeScan(controller, value: FlutterError(code: "scan_failed",
      message: error.localizedDescription, details: nil))
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
  ) {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("score-scan-\(UUID().uuidString).pdf")
    let sheet = CGRect(x: 0, y: 0, width: 612, height: 792)
    let renderer = UIGraphicsPDFRenderer(bounds: sheet)
    do {
      try renderer.writePDF(to: url) { context in
        for index in 0..<scan.pageCount {
          autoreleasepool {
            let image = scan.imageOfPage(at: index)
            let scale = min(sheet.width / image.size.width, sheet.height / image.size.height)
            let frame = CGRect(x: 0, y: 0, width: image.size.width * scale,
                               height: image.size.height * scale)
            context.beginPage(withBounds: frame, pageInfo: [:])
            image.draw(in: frame)
          }
        }
      }
      completeScan(controller, value: url.path)
    } catch {
      completeScan(controller, value: FlutterError(code: "scan_pdf",
        message: error.localizedDescription, details: nil))
    }
  }

  private func completeScan(_ controller: VNDocumentCameraViewController, value: Any?) {
    let result = scanResult
    controller.dismiss(animated: true) { [weak self] in
      self?.scanResult = nil
      result?(value)
    }
  }

  func receivePDF(_ url: URL) {
    guard url.isFileURL, url.pathExtension.lowercased() == "pdf" else { return }
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let target = folder.appendingPathComponent(url.lastPathComponent)
      try FileManager.default.copyItem(at: url, to: target)
      pendingPdfs.append(target.path)
      importChannel?.invokeMethod("available", arguments: nil)
    } catch {
      NSLog("Could not stage PDF import: %@", error.localizedDescription)
    }
  }
}
