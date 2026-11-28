import Flutter
import PDFKit
import UIKit
import UniformTypeIdentifiers

class SceneDelegate: FlutterSceneDelegate, UIPencilInteractionDelegate, UIDropInteractionDelegate {
  private var pencilInteraction: UIPencilInteraction?
  private var scoreDrop: UIDropInteraction?

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
      let drop = UIDropInteraction(delegate: self)
      view.addInteraction(drop)
      scoreDrop = drop
    }
    receive(connectionOptions.urlContexts)
  }

  func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
    session.hasItemsConforming(toTypeIdentifiers: [UTType.pdf.identifier, UTType.audio.identifier])
  }

  func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession)
    -> UIDropProposal {
    UIDropProposal(operation: .copy)
  }

  func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
    guard let delegate = UIApplication.shared.delegate as? AppDelegate else { return }
    let staging = DispatchGroup()
    var staged = [Int: String]()
    for (index, item) in session.items.prefix(20).enumerated() {
      let provider = item.itemProvider
      let type = provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
        ? UTType.pdf
        : provider.registeredTypeIdentifiers.compactMap { UTType($0) }
          .first { $0.conforms(to: .audio) && $0.preferredFilenameExtension != nil }
      guard let type, let fileExtension = type.preferredFilenameExtension else { continue }
      let label = provider.suggestedName
      staging.enter()
      provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
        guard let url else { staging.leave(); return }
        let path: String
        do {
          path = try AppDelegate.stageDroppedFile(url, name: label, fileExtension: fileExtension)
        } catch {
          NSLog("Could not stage dropped score file: %@", error.localizedDescription)
          staging.leave()
          return
        }
        DispatchQueue.main.async {
          staged[index] = path
          staging.leave()
        }
      }
    }
    staging.notify(queue: .main) {
      delegate.receiveStagedDrops(staged.keys.sorted().compactMap { staged[$0] })
    }
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
    for context in contexts {
      if context.url.scheme == "encoresheets" {
        delegate.receiveScoreLink(context.url)
      } else {
        delegate.receivePDF(context.url)
      }
    }
  }
}

final class ScoreWindowSceneDelegate: UIResponder, UIWindowSceneDelegate {
  static let activityType = "app.encoresheets.score-window"
  var window: UIWindow?
  private weak var pdfView: PDFView?
  private weak var reader: UIViewController?
  private var activity: NSUserActivity?
  private var scoreURL: URL?
  private var positions: [URL: Int] = [:]

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options: UIScene.ConnectionOptions
  ) {
    guard let scene = scene as? UIWindowScene else { return }
    let controller = UIViewController()
    let view = PDFView()
    controller.view = view
    reader = controller
    view.autoScales = true
    view.displayMode = .singlePageContinuous
    let activity = options.userActivities.first { $0.activityType == Self.activityType }
      ?? session.stateRestorationActivity
    self.activity = activity
    self.pdfView = view
    controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
      title: "Scores", style: .plain, target: self, action: #selector(showScores)
    )
    controller.navigationItem.rightBarButtonItems = [
      UIBarButtonItem(title: "Next", style: .plain, target: self, action: #selector(nextPage)),
      UIBarButtonItem(title: "Previous", style: .plain, target: self, action: #selector(previousPage)),
      UIBarButtonItem(title: "Fit", style: .plain, target: self, action: #selector(fitPage)),
    ]
    let navigation = UINavigationController(rootViewController: controller)
    let window = UIWindow(windowScene: scene)
    window.rootViewController = navigation
    window.makeKeyAndVisible()
    self.window = window
    if let data = activity?.userInfo, let path = data["path"] as? String {
      openScore(
        at: URL(fileURLWithPath: path), title: data["title"] as? String ?? "Score",
        page: data["page"] as? Int ?? 1
      )
    } else {
      controller.title = "Choose a score"
    }
  }

  private var scoresDirectory: URL? {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
      .appendingPathComponent("LibraryData/scores", isDirectory: true)
      .resolvingSymlinksInPath()
  }

  private func openScore(at url: URL, title: String, page: Int) {
    let resolved = url.resolvingSymlinksInPath().standardizedFileURL
    guard let view = pdfView, let directory = scoresDirectory,
          resolved.deletingLastPathComponent().path == directory.path,
          resolved.pathExtension.lowercased() == "pdf",
          let document = PDFDocument(url: resolved), document.pageCount > 0 else {
      let alert = UIAlertController(title: "Score unavailable", message: nil, preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "OK", style: .default))
      reader?.present(alert, animated: true)
      return
    }
    rememberPage()
    scoreURL = resolved
    view.document = document
    view.autoScales = true
    let target = min(document.pageCount, max(1, positions[resolved] ?? page))
    if let pdfPage = document.page(at: target - 1) { view.go(to: pdfPage) }
    reader?.title = title
    window?.windowScene?.title = title
    let restored = NSUserActivity(activityType: Self.activityType)
    restored.userInfo = ["path": resolved.path, "title": title, "page": target]
    activity = restored
  }

  private func rememberPage() {
    if let url = scoreURL, let view = pdfView,
       let current = view.currentPage, let document = view.document {
      positions[url] = document.index(for: current) + 1
    }
  }

  @objc private func previousPage() { pdfView?.goToPreviousPage(nil) }
  @objc private func nextPage() { pdfView?.goToNextPage(nil) }
  @objc private func fitPage() {
    if let view = pdfView { view.scaleFactor = view.scaleFactorForSizeToFit }
  }

  @objc private func showScores() {
    guard let directory = scoresDirectory else { return }
    let catalog = (UIApplication.shared.delegate as? AppDelegate)?.scoreWindowCatalog ?? []
    let rows: [ScoreWindowPicker.Row] = catalog.compactMap { row in
      guard let id = row["file"] as? String,
            id.range(of: "^[a-zA-Z0-9-]+$", options: .regularExpression) != nil,
            let title = row["title"] as? String else { return nil }
      return (directory.appendingPathComponent("\(id).pdf"), title, row["page"] as? Int ?? 1)
    }
    let picker = ScoreWindowPicker(rows: rows) { [weak self] row in
      self?.openScore(at: row.url, title: row.title, page: row.page)
    }
    reader?.present(UINavigationController(rootViewController: picker), animated: true)
  }

  func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
    rememberPage()
    if let url = scoreURL, let page = positions[url] {
      activity?.addUserInfoEntries(from: ["page": page])
    }
    return activity
  }
}

private final class ScoreWindowPicker: UITableViewController, UISearchResultsUpdating {
  typealias Row = (url: URL, title: String, page: Int)
  private let rows: [Row]
  private var filtered: [Row]
  private let select: (Row) -> Void

  init(rows: [Row], select: @escaping (Row) -> Void) {
    let sorted = rows.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    self.rows = sorted
    self.filtered = sorted
    self.select = select
    super.init(style: .insetGrouped)
  }

  required init?(coder: NSCoder) { return nil }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Choose a score"
    let search = UISearchController(searchResultsController: nil)
    search.searchResultsUpdater = self
    search.obscuresBackgroundDuringPresentation = false
    search.searchBar.placeholder = "Search scores"
    navigationItem.searchController = search
    navigationItem.hidesSearchBarWhenScrolling = false
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .cancel, target: self, action: #selector(close)
    )
  }

  @objc private func close() { dismiss(animated: true) }

  func updateSearchResults(for searchController: UISearchController) {
    let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    filtered = query.isEmpty ? rows : rows.filter { $0.title.localizedCaseInsensitiveContains(query) }
    tableView.reloadData()
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    if filtered.isEmpty {
      let message = UILabel()
      message.text = rows.isEmpty ? "No scores available in this window." : "No matching scores."
      message.textAlignment = .center
      message.textColor = .secondaryLabel
      tableView.backgroundView = message
    } else {
      tableView.backgroundView = nil
    }
    return filtered.count
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "score") ??
      UITableViewCell(style: .default, reuseIdentifier: "score")
    var content = cell.defaultContentConfiguration()
    content.text = filtered[indexPath.row].title
    cell.contentConfiguration = content
    return cell
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    let row = filtered[indexPath.row]
    dismiss(animated: true) { [select] in select(row) }
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
