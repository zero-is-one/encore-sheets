import Flutter
import UIKit
import VisionKit
import UniformTypeIdentifiers
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  VNDocumentCameraViewControllerDelegate, UIDocumentPickerDelegate, MPMediaPickerControllerDelegate {
  private var importChannel: FlutterMethodChannel?
  private var stylusChannel: FlutterMethodChannel?
  private var pendingPdfs: [String] = []
  private var scanResult: FlutterResult?
  private var folderResult: FlutterResult?
  private var musicPickerResult: FlutterResult?
  private var musicTrackID: MPMediaEntityPersistentID?
  var presentedScore: (path: String, page: Int)?
  nonisolated private let syncBookmark = "librarySyncFolder"
  private let syncQueue = DispatchQueue(label: "app.encoresheets.library-sync")
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    stylusChannel = FlutterMethodChannel(
      name: "encoresheets/stylus",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
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
    let sync = FlutterMethodChannel(
      name: "encoresheets/library-sync",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    sync.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      self.handleSync(call, result: result)
    }
    let music = FlutterMethodChannel(
      name: "encoresheets/music",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    music.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handleMusic(call, result: result)
    }
    let windows = FlutterMethodChannel(
      name: "encoresheets/score-windows",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    windows.setMethodCallHandler { call, result in
      guard call.method == "open",
        let data = call.arguments as? [String: Any],
        let path = data["path"] as? String,
        let title = data["title"] as? String,
        let page = data["page"] as? Int else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard UIApplication.shared.supportsMultipleScenes else {
        result(FlutterError(code: "windows_unavailable", message: "This device does not support multiple app windows.", details: nil))
        return
      }
      let activity = NSUserActivity(activityType: ScoreWindowSceneDelegate.activityType)
      activity.userInfo = ["path": path, "title": title, "page": page]
      UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: nil) { error in
        NSLog("EncoreSheets could not open the score window: %@", error.localizedDescription)
      }
      result(nil)
    }
    let presentation = FlutterMethodChannel(
      name: "encoresheets/presentation",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    presentation.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "hide":
        self.presentedScore = nil
      case "show":
        guard let data = call.arguments as? [String: Any],
          let path = data["path"] as? String,
          let page = data["page"] as? Int else {
          result(FlutterMethodNotImplemented)
          return
        }
        self.presentedScore = (path, page)
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      for scene in UIApplication.shared.connectedScenes {
        (scene.delegate as? ScorePresentationSceneDelegate)?.refresh()
      }
      result(nil)
    }
  }

  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
      let configuration = UISceneConfiguration(name: "Score presentation", sessionRole: connectingSceneSession.role)
      configuration.delegateClass = ScorePresentationSceneDelegate.self
      return configuration
    }
    if options.userActivities.contains(where: { $0.activityType == ScoreWindowSceneDelegate.activityType }) {
      let configuration = UISceneConfiguration(name: "Score window", sessionRole: connectingSceneSession.role)
      configuration.delegateClass = ScoreWindowSceneDelegate.self
      return configuration
    }
    return UISceneConfiguration(name: "flutter", sessionRole: connectingSceneSession.role)
  }

  private func handleMusic(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let player = MPMusicPlayerController.applicationMusicPlayer
    switch call.method {
    case "pick":
      guard musicPickerResult == nil else {
        result(FlutterError(code: "music_busy", message: "The Music picker is already open.", details: nil))
        return
      }
      musicPickerResult = result
      MPMediaLibrary.requestAuthorization { [weak self] status in
        DispatchQueue.main.async {
          guard let self else { return }
          guard status == .authorized, let presenter = self.frontController else {
            self.musicPickerResult = nil
            result(FlutterError(code: "music_permission", message: "Allow access to your Music library.", details: nil))
            return
          }
          let picker = MPMediaPickerController(mediaTypes: .music)
          picker.delegate = self
          picker.allowsPickingMultipleItems = false
          picker.showsCloudItems = true
          presenter.present(picker, animated: true)
        }
      }
    case "toggle":
      guard let idText = call.arguments as? String, let id = UInt64(idText),
            MPMediaLibrary.authorizationStatus() == .authorized else {
        result(FlutterError(code: "music_permission", message: "The linked Music track is unavailable.", details: nil))
        return
      }
      if musicTrackID == id && player.playbackState == .playing {
        player.pause()
        result(false)
        return
      }
      if musicTrackID != id || player.nowPlayingItem?.persistentID != id {
        let query = MPMediaQuery.songs()
        query.addFilterPredicate(MPMediaPropertyPredicate(
          value: NSNumber(value: id), forProperty: MPMediaItemPropertyPersistentID
        ))
        guard let item = query.items?.first else {
          result(FlutterError(code: "music_missing", message: "This track is no longer in your Music library.", details: nil))
          return
        }
        player.setQueue(with: MPMediaItemCollection(items: [item]))
        musicTrackID = id
      }
      player.play()
      result(true)
    case "pause":
      player.pause()
      result(nil)
    case "stop":
      player.stop()
      musicTrackID = nil
      result(nil)
    case "isPlaying":
      let selected = (call.arguments as? String).flatMap { UInt64($0) }
      result(selected != nil && selected == musicTrackID && player.playbackState == .playing)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func mediaPicker(_ mediaPicker: MPMediaPickerController,
                   didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
    let selected = mediaItemCollection.items.first.map {
      ["id": String($0.persistentID), "title": $0.title ?? "Music track"]
    }
    finishMusicPicker(mediaPicker, value: selected)
  }

  func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
    finishMusicPicker(mediaPicker, value: nil)
  }

  private func finishMusicPicker(_ picker: MPMediaPickerController, value: [String: String]?) {
    let result = musicPickerResult
    musicPickerResult = nil
    picker.dismiss(animated: true) { result?(value) }
  }

  func notifyPencilTap() {
    stylusChannel?.invokeMethod("switchTool", arguments: nil)
  }

  private var frontController: UIViewController? {
    var controller = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.delegate is SceneDelegate }
      .flatMap { $0.windows }
      .first(where: { $0.isKeyWindow })?.rootViewController
    while let next = controller?.presentedViewController { controller = next }
    return controller
  }

  private func handleSync(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "configured":
      result(UserDefaults.standard.data(forKey: syncBookmark) != nil)
    case "disconnect":
      UserDefaults.standard.removeObject(forKey: syncBookmark)
      result(nil)
    case "chooseFolder":
      guard folderResult == nil, let presenter = frontController else {
        result(FlutterError(code: "sync_picker", message: "Could not open Files.", details: nil))
        return
      }
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
      picker.delegate = self
      folderResult = result
      presenter.present(picker, animated: true)
    case "readDevices", "writeDevice", "fetchPdf", "publishPdf":
      let method = call.method
      let args = call.arguments as? [String: String] ?? [:]
      syncQueue.async {
        do {
          let value = try self.performSync(method, args: args)
          DispatchQueue.main.async { result(value) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "sync_io", message: error.localizedDescription, details: nil))
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController,
                      didPickDocumentsAt urls: [URL]) {
    let result = folderResult
    folderResult = nil
    guard let url = urls.first, url.startAccessingSecurityScopedResource() else {
      result?(false)
      return
    }
    defer { url.stopAccessingSecurityScopedResource() }
    do {
      let data = try url.bookmarkData(options: .minimalBookmark)
      UserDefaults.standard.set(data, forKey: syncBookmark)
      result?(true)
    } catch {
      result?(FlutterError(code: "sync_bookmark", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let result = folderResult
    folderResult = nil
    result?(false)
  }

  nonisolated private func performSync(_ method: String, args: [String: String]) throws -> Any? {
    let files = FileManager.default
    guard let bookmark = UserDefaults.standard.data(forKey: syncBookmark) else {
      throw CocoaError(.fileReadNoSuchFile)
    }
    var stale = false
    let selected = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI],
                           relativeTo: nil, bookmarkDataIsStale: &stale)
    guard selected.startAccessingSecurityScopedResource() else {
      throw CocoaError(.fileReadNoPermission)
    }
    defer { selected.stopAccessingSecurityScopedResource() }
    if stale {
      let fresh = try selected.bookmarkData(options: .minimalBookmark)
      UserDefaults.standard.set(fresh, forKey: syncBookmark)
    }
    let root = selected.appendingPathComponent("EncoreSheets Sync", isDirectory: true)
    try files.createDirectory(at: root, withIntermediateDirectories: true)
    if method == "readDevices" {
      let urls = try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
      var records: [String: String] = [:]
      for file in urls where file.pathExtension == "json" && file.lastPathComponent.hasPrefix("device-") {
        let id = String(file.deletingPathExtension().lastPathComponent.dropFirst(7))
        guard id.range(of: "^[a-zA-Z0-9-]{1,80}$", options: .regularExpression) != nil else { continue }
        records[id] = try withCoordinatedRead(file) { try String(contentsOf: $0, encoding: .utf8) }
      }
      return records
    }
    guard let id = args["id"],
          id.range(of: "^[a-zA-Z0-9-]{1,80}$", options: .regularExpression) != nil else {
      throw CocoaError(.fileReadInvalidFileName)
    }
    if method == "writeDevice", let json = args["json"] {
      let target = root.appendingPathComponent("device-\(id).json")
      try withCoordinatedWrite(target) { try Data(json.utf8).write(to: $0, options: .atomic) }
      return nil
    }
    let sharedPdf = root.appendingPathComponent("score-\(id).pdf")
    if method == "publishPdf", let path = args["path"] {
      try withCoordinatedWrite(sharedPdf) { target in
        if !files.fileExists(atPath: target.path) {
          try files.copyItem(at: URL(fileURLWithPath: path), to: target)
        }
      }
      return nil
    }
    if method == "fetchPdf" {
      let target = files.temporaryDirectory.appendingPathComponent("sync-\(UUID().uuidString).pdf")
      try withCoordinatedRead(sharedPdf) { try files.copyItem(at: $0, to: target) }
      return target.path
    }
    throw CocoaError(.fileReadUnknown)
  }

  nonisolated private func withCoordinatedRead<T>(
    _ url: URL, work: (URL) throws -> T
  ) throws -> T {
    if FileManager.default.isUbiquitousItem(at: url) {
      try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
    var failure: NSError?
    var result: Result<T, Error>?
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &failure) { path in
      result = Result { try work(path) }
    }
    if let failure { throw failure }
    guard let result else { throw CocoaError(.fileReadUnknown) }
    return try result.get()
  }

  nonisolated private func withCoordinatedWrite(_ url: URL, work: (URL) throws -> Void) throws {
    var failure: NSError?
    var result: Result<Void, Error>?
    NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &failure) { path in
      result = Result { try work(path) }
    }
    if let failure { throw failure }
    guard let result else { throw CocoaError(.fileWriteUnknown) }
    return try result.get()
  }

  private func startScan(_ result: @escaping FlutterResult) {
    guard VNDocumentCameraViewController.isSupported, scanResult == nil,
          let presenter = frontController else {
      result(FlutterError(code: "scan_unavailable",
                          message: "The document scanner is unavailable.", details: nil))
      return
    }
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
