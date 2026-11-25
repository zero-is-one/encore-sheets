import Flutter
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
