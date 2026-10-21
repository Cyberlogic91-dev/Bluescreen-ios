import UIKit
import AVFoundation

/// BlueScreen — jeu de cartes édité par CYBERLOGIC.
/// Le jeu tourne hors ligne dans une WKWebView (même code que la version Android).
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let game = GameViewController()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // la musique du jeu respecte le bouton silencieux et se mélange aux autres sons
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        application.isIdleTimerDisabled = true          // l'écran reste allumé pendant les parties
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = game
        w.backgroundColor = UIColor(red: 10 / 255, green: 27 / 255, blue: 61 / 255, alpha: 1)
        w.makeKeyAndVisible()
        window = w
        return true
    }

    /// Retour de la connexion Discord : fr.cyberlogic.ecranbleu:/oauth?code=…&state=…
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard url.scheme == "fr.cyberlogic.ecranbleu" else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func v(_ k: String) -> String { items.first { $0.name == k }?.value ?? "" }
        let js = "window.EBAuth&&EBAuth.onReturn(\(JS.quote(v("code"))),\(JS.quote(v("state"))),\(JS.quote(v("error"))))"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.game.callJs(js) }
        return true
    }
}

/// Petits utilitaires JavaScript.
enum JS {
    /// Chaîne JavaScript correctement échappée (équivalent de JSONObject.quote côté Android).
    static func quote(_ s: String) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: [s]), var t = String(data: d, encoding: .utf8) else { return "\"\"" }
        t.removeFirst(); t.removeLast()
        return t
    }
}
