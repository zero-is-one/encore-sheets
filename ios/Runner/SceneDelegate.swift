import Flutter
import PDFKit
import UIKit

class SceneDelegate: FlutterSceneDelegate, UIPencilInteractionDelegate {
  private var pencilInteraction: UIPencilInteraction?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if pencilInteraction == nil,
       let view = (scene as? UIWindowScene)?.windows.first?.rootViewController?.view {
      let interaction = UIPencilInteraction()
      interaction.delegate = self
      view.addInteraction(interaction)
      pencilInteraction = interaction
    }
    receive(connectionOptions.urlContexts)
  }

  func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
    handlePencilTap()
  }

  @available(iOS 17.5, *)
  func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
    handlePencilTap()
  }

  private func handlePencilTap() {
    guard UIPencilInteraction.preferredTapAction != .ignore else { return }
    (UIApplication.shared.delegate as? AppDelegate)?.notifyPencilTap()
  }

  override func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: contexts)
    receive(contexts)
  }

  private func receive(_ contexts: Set<UIOpenURLContext>) {
    guard let delegate = UIApplication.shared.delegate as? AppDelegate else { return }
    for context in contexts { delegate.receivePDF(context.url) }
  }
}

final class ScoreWindowSceneDelegate: UIResponder, UIWindowSceneDelegate {
  static let activityType = "app.encoresheets.score-window"
  var window: UIWindow?
  private weak var pdfView: PDFView?
  private var activity: NSUserActivity?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options: UIScene.ConnectionOptions
  ) {
    guard let scene = scene as? UIWindowScene else { return }
    let controller = UIViewController()
    let view = PDFView()
    controller.view = view
    view.autoScales = true
    view.displayMode = .singlePageContinuous
    let activity = options.userActivities.first { $0.activityType == Self.activityType }
      ?? session.stateRestorationActivity
    self.activity = activity
    self.pdfView = view
    if let data = activity?.userInfo,
       let path = data["path"] as? String,
       let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
       URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(support.path + "/LibraryData/"),
       let document = PDFDocument(url: URL(fileURLWithPath: path)) {
      view.document = document
      if let index = data["page"] as? Int, let page = document.page(at: max(0, index - 1)) {
        view.go(to: page)
      }
      scene.title = data["title"] as? String
    } else {
      let label = UILabel()
      label.text = "This score is unavailable."
      label.textAlignment = .center
      controller.view = label
    }
    let window = UIWindow(windowScene: scene)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    self.window = window
  }

  func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
    if let view = pdfView, let current = view.currentPage, let document = view.document {
      activity?.addUserInfoEntries(from: ["page": document.index(for: current) + 1])
    }
    return activity
  }
}

final class ScorePresentationSceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private weak var scene: UIWindowScene?
  private var view: PDFView?
  private var path: String?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
             options: UIScene.ConnectionOptions) {
    self.scene = scene as? UIWindowScene
    refresh()
  }

  func refresh() {
    guard let scene,
      let state = (UIApplication.shared.delegate as? AppDelegate)?.presentedScore else {
      window?.isHidden = true
      window?.windowScene = nil
      window = nil
      view = nil
      path = nil
      return
    }
    if view == nil {
      let pdf = PDFView()
      pdf.autoScales = true
      pdf.displayMode = .singlePage
      pdf.isUserInteractionEnabled = false
      pdf.backgroundColor = .black
      let controller = UIViewController()
      controller.view = pdf
      let window = UIWindow(windowScene: scene)
      window.rootViewController = controller
      window.isHidden = false
      self.window = window
      view = pdf
    }
    if path != state.path {
      view?.document = PDFDocument(url: URL(fileURLWithPath: state.path))
      path = state.path
    }
    if let page = view?.document?.page(at: max(0, state.page - 1)) {
      view?.go(to: page)
    }
  }
}
