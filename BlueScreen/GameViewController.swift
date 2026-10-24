import UIKit
import WebKit
import AVFoundation

/// Affiche le jeu (www/index.html) et fournit à la page le même pont `window.EBHost` que l'appli Android.
/// Les méthodes qui renvoient une valeur passent par `prompt()` (réponse synchrone côté JavaScript),
/// les autres par un message WebKit (sans attente).
final class GameViewController: UIViewController, WKUIDelegate, WKScriptMessageHandler, WKNavigationDelegate,
                                UIImagePickerControllerDelegate, UINavigationControllerDelegate, AVSpeechSynthesizerDelegate {
    private var web: WKWebView!
    private var server: GameServer?
    private let speech = AVSpeechSynthesizer()
    private lazy var bundleWww: URL = Bundle.main.url(forResource: "www", withExtension: nil)!
    /// Dossier de jeu : la mise à jour rapide si elle correspond à cette appli, sinon le jeu livré avec l'appli.
    private var wwwDir: URL { Updater.activeDir(bundle: bundleWww) }
    private var homeURL: URL { wwwDir.appendingPathComponent("index.html") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func loadView() {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let ucc = WKUserContentController()
        ucc.add(WeakHandler(self), name: "eb")
        ucc.addUserScript(WKUserScript(source: Self.bridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController = ucc
        web = WKWebView(frame: .zero, configuration: cfg)
        web.uiDelegate = self
        web.navigationDelegate = self
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 10 / 255, green: 27 / 255, blue: 61 / 255, alpha: 1)
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 16.4, *) { web.isInspectable = true }   // débogage depuis Safari sur Mac
        view = web
        speech.delegate = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        goHome()
    }

    func goHome() { web.loadFileURL(homeURL, allowingReadAccessTo: wwwDir) }

    /// Exécute du JavaScript dans la page (depuis n'importe quel fil).
    func callJs(_ js: String) {
        DispatchQueue.main.async { self.web.evaluateJavaScript(js, completionHandler: nil) }
    }

    // MARK: - Pont JavaScript

    /// Le même objet que `window.EBHost` sur Android.
    private static let bridgeJS = """
    (function () {
      function call(m, a) { var r = window.prompt("EBHost:" + m, JSON.stringify(a || [])); return r == null ? "" : r; }
      function post(m, a) { try { window.webkit.messageHandlers.eb.postMessage({m: m, a: a || []}); } catch (e) {} }
      window.EBHost = {
        startServer: function () { return call("startServer"); },
        stopServer: function () { post("stopServer"); },
        publish: function (pid, json) { post("publish", [pid, json]); },
        openUrl: function (u) { post("openUrl", [u]); },
        goHome: function () { post("goHome"); },
        vibrate: function (p) { post("vibrate", [String(p)]); },
        openExternal: function (u) { post("openExternal", [u]); },
        postForm: function (u, b) { return call("postForm", [u, b]); },
        getBearer: function (u, t) { return call("getBearer", [u, t]); },
        fetchImage: function (u) { return call("fetchImage", [u]); },
        packageName: function () { return "fr.cyberlogic.ecranbleu"; },
        share: function (t) { post("share", [t]); },
        speak: function (t, p, r) { post("speak", [t, p, r]); },
        stopSpeak: function () { post("stopSpeak"); },
        hasVoice: function () { return true; },
        takePhoto: function () { post("takePhoto"); },
        nativeVersion: function () { return 2; },
        platform: function () { return "ios"; },
        hotUpdate: function (u, v) { post("hotUpdate", [u, v]); },
        openApp: function (u) { post("openApp", [u]); },
        resetUpdate: function () { post("resetUpdate"); }
      };
    })();
    """

    /// Méthodes sans valeur de retour.
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let m = body["m"] as? String else { return }
        let a = body["a"] as? [Any] ?? []
        func s(_ i: Int) -> String { i < a.count ? "\(a[i])" : "" }
        func f(_ i: Int) -> Float { i < a.count ? Float("\(a[i])") ?? 1 : 1 }
        switch m {
        case "publish": server?.publish(pid: s(0), json: s(1))
        case "stopServer": server?.stop(); server = nil
        case "openUrl": if let u = URL(string: s(0)) { web.load(URLRequest(url: u)) }
        case "goHome": goHome()
        case "vibrate": vibrate(s(0))
        case "openExternal": if s(0).hasPrefix("https://"), let u = URL(string: s(0)) { UIApplication.shared.open(u) }
        case "share": share(s(0))
        case "speak": speak(s(0), pitch: f(1), rate: f(2))
        case "stopSpeak": speech.stopSpeaking(at: .immediate)
        case "takePhoto": takePhoto()
        case "hotUpdate":
            Updater.hotUpdate(url: s(0), version: s(1), bundle: bundleWww) { [weak self] ok, msg in
                self?.callJs("window.Update&&Update._hot(\(ok),\(JS.quote(msg)))")
            }
        case "openApp": if s(0).hasPrefix("altstore://"), let u = URL(string: s(0)) { UIApplication.shared.open(u) }
        case "resetUpdate": Updater.reset()
        default: break
        }
    }

    /// Méthodes qui renvoient une valeur : la page attend la réponse (prompt synchrone).
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard prompt.hasPrefix("EBHost:") else {
            // vrai prompt d'une page : fenêtre classique
            let al = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            al.addTextField { $0.text = defaultText }
            al.addAction(UIAlertAction(title: "Annuler", style: .cancel) { _ in completionHandler(nil) })
            al.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(al.textFields?.first?.text) })
            present(al, animated: true); return
        }
        let m = String(prompt.dropFirst("EBHost:".count))
        let a = (try? JSONSerialization.jsonObject(with: Data((defaultText ?? "[]").utf8))) as? [String] ?? []
        func s(_ i: Int) -> String { i < a.count ? a[i] : "" }
        switch m {
        case "startServer": completionHandler(startServer())
        case "postForm": Net.request(method: "POST", url: s(0), body: s(1), bearer: nil, completion: completionHandler)
        case "getBearer": Net.request(method: "GET", url: s(0), body: nil, bearer: s(1), completion: completionHandler)
        case "fetchImage": Net.imageDataURL(s(0), completion: completionHandler)
        default: completionHandler("")
        }
    }

    // fenêtres alert()/confirm() de la page
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let al = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        al.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(al, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let al = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        al.addAction(UIAlertAction(title: "Annuler", style: .cancel) { _ in completionHandler(false) })
        al.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(al, animated: true)
    }

    // liens externes (site CYBERLOGIC…) : ouverts dans Safari
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let u = action.request.url, u.scheme == "https", action.navigationType == .linkActivated {
            UIApplication.shared.open(u); decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    // MARK: - Partie Wi-Fi (ce téléphone devient l'hôte)

    private func startServer() -> String {
        var err: String? = nil
        if server == nil {
            let s = GameServer(indexURL: homeURL) { [weak self] js in self?.callJs(js) }
            do { try s.start(); server = s } catch { err = "Impossible d'ouvrir le port : \(error.localizedDescription)" }
        }
        var url = ""
        if err == nil {
            if let ip = Net.localIPv4(), let port = server?.port { url = "http://\(ip):\(port)/" }
            else { err = "Aucune adresse Wi-Fi trouvée (connecte ce téléphone au Wi-Fi ou active le partage de connexion)" }
        }
        var obj: [String: Any] = ["url": url]
        obj["error"] = err.map { $0 as Any } ?? NSNull()
        let d = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        return String(data: d, encoding: .utf8) ?? "{}"
    }

    // MARK: - Vibration, partage, voix

    private func vibrate(_ pattern: String) {
        let parts = pattern.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        let gen = UIImpactFeedbackGenerator(style: (parts.first ?? 0) > 150 ? .heavy : .medium)
        gen.prepare()
        var t = 0.0
        for (i, ms) in parts.enumerated() {
            if i % 2 == 0 { DispatchQueue.main.asyncAfter(deadline: .now() + t) { gen.impactOccurred() } }
            t += ms / 1000
        }
        if parts.isEmpty { gen.impactOccurred() }
    }

    private func share(_ text: String) {
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = view
        vc.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(vc, animated: true)
    }

    private func speak(_ text: String, pitch: Float, rate: Float) {
        speech.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        u.pitchMultiplier = max(0.5, min(2, pitch))
        u.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * max(0.5, min(2, rate))))
        speech.speak(u)
    }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { callJs("window.Voice&&Voice._end&&Voice._end()") }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { callJs("window.Voice&&Voice._end&&Voice._end()") }

    // MARK: - Appareil photo (avatar)

    private func takePhoto() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            callJs("window.onCameraPhoto&&onCameraPhoto(null,'Aucun appareil photo disponible.')"); return
        }
        let p = UIImagePickerController()
        p.sourceType = .camera
        if UIImagePickerController.isCameraDeviceAvailable(.front) { p.cameraDevice = .front }
        p.delegate = self
        present(p, animated: true)
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true); callJs("window.onCameraPhoto&&onCameraPhoto(null,'')")
    }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let img = info[.originalImage] as? UIImage else { callJs("window.onCameraPhoto&&onCameraPhoto(null,'Photo illisible, réessaie.')"); return }
        // carré centré de 360 px (l'orientation est corrigée par le dessin)
        let side: CGFloat = 360, m = min(img.size.width, img.size.height), k = side / m
        let r = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let out = r.image { _ in img.draw(in: CGRect(x: -(img.size.width - m) / 2 * k, y: -(img.size.height - m) / 2 * k, width: img.size.width * k, height: img.size.height * k)) }
        guard let jpg = out.jpegData(compressionQuality: 0.88) else { return }
        callJs("window.onCameraPhoto&&onCameraPhoto(\(JS.quote("data:image/jpeg;base64," + jpg.base64EncodedString())),'')")
    }
}

/// Évite le cycle de rétention entre WKUserContentController et le contrôleur.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(ucc, didReceive: message)
    }
}
