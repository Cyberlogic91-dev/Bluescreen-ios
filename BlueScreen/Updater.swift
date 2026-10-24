import Foundation
import CryptoKit

/// Mise à jour rapide : la page du jeu est téléchargée depuis jeu.cyberlogic.fr et rangée dans
/// Application Support/www (avec une copie des musiques et du logo). Elle est oubliée dès qu'une
/// nouvelle version de l'appli est installée (via AltStore), qui contient une page au moins aussi récente.
enum Updater {
    static let base = "https://jeu.cyberlogic.fr/"
    static let pageURL = URL(string: base + "app/index.html")!, sigURL = URL(string: base + "app/index.sig")!
    /// Clé publique CYBERLOGIC (ECDSA P-256, DER) : seule une page signée par la clé privée correspondante est acceptée.
    static let publicKeyDER = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEBzWlAfCnMZbyXBwXdIwl7GIp47AmIWcjKDgQkWa7wgiVDK4tQV7K1aXJaeQigUjqxVlbDKVQVtbyrixx3Od1Yw=="

    static func verify(_ data: Data, signatureB64: String) -> Bool {
        guard let kd = Data(base64Encoded: publicKeyDER), let key = try? P256.Signing.PublicKey(derRepresentation: kd),
              let sd = Data(base64Encoded: signatureB64.trimmingCharacters(in: .whitespacesAndNewlines)),
              let sig = try? P256.Signing.ECDSASignature(derRepresentation: sd) else { return false }
        return key.isValidSignature(sig, for: data)
    }

    static func cmp(_ a: String, _ b: String) -> Int {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q ? 1 : -1 }
        }
        return 0
    }
    private static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    private static let d = UserDefaults.standard

    static var dir: URL {
        let sup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return sup.appendingPathComponent("www", isDirectory: true)
    }
    private static var appBuild: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }

    static func activeDir(bundle: URL) -> URL {
        let page = dir.appendingPathComponent("index.html")
        if d.string(forKey: "upd_build") == appBuild, FileManager.default.fileExists(atPath: page.path) { return dir }
        if d.string(forKey: "upd_build") != nil { reset() }
        return bundle
    }

    static func reset() {
        d.removeObject(forKey: "upd_build"); d.removeObject(forKey: "upd_ver")
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("index.html"))
    }

    static func hotUpdate(url: String, version: String, bundle: URL, done: @escaping (Bool, String) -> Void) {
        func finish(_ ok: Bool, _ msg: String) { DispatchQueue.main.async { done(ok, msg) } }
        guard version.range(of: "^[0-9]+(\\.[0-9]+){0,3}$", options: .regularExpression) != nil else { return finish(false, "version invalide") }
        // jamais de retour en arrière : plus récente que l'appli ET que la mise à jour déjà installée
        guard cmp(version, appVersion) > 0, cmp(version, d.string(forKey: "upd_ver") ?? "0") > 0 else { return finish(false, "version déjà installée") }
        func fetch(_ u: URL, _ done: @escaping (Data?) -> Void) {
            var c = URLComponents(url: u, resolvingAgainstBaseURL: false)!
            c.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]
            var req = URLRequest(url: c.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            req.setValue("BlueScreen-iOS", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200, http.url?.host == "jeu.cyberlogic.fr" else { return done(nil) }
                done(data)
            }.resume()
        }
        fetch(sigURL) { sigData in
          guard let sigData = sigData, sigData.count < 4096, let sigB64 = String(data: sigData, encoding: .ascii) else { return finish(false, "signature introuvable") }
          fetch(pageURL) { data in
            guard let data = data, data.count > 100_000, data.count < 8_000_000 else { return finish(false, "téléchargement impossible") }
            guard verify(data, signatureB64: sigB64) else { return finish(false, "signature CYBERLOGIC invalide") }
            guard let html = String(data: data, encoding: .utf8), html.contains("const APP_VERSION = \"\(version)\""), html.contains("EBHost") else { return finish(false, "fichier inattendu") }
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                // musiques et logo à côté de la page
                if let items = try? fm.contentsOfDirectory(at: bundle, includingPropertiesForKeys: nil) {
                    for it in items where it.lastPathComponent != "index.html" {
                        let dst = dir.appendingPathComponent(it.lastPathComponent)
                        if !fm.fileExists(atPath: dst.path) { try fm.copyItem(at: it, to: dst) }
                    }
                }
                try data.write(to: dir.appendingPathComponent("index.html"), options: .atomic)
                d.set(appBuild, forKey: "upd_build"); d.set(version, forKey: "upd_ver")
                finish(true, "")
            } catch { finish(false, error.localizedDescription) }
          }
        }
    }
}
