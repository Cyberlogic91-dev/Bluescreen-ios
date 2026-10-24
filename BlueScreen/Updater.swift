import Foundation

/// Mise à jour rapide : la page du jeu est téléchargée depuis jeu.cyberlogic.fr et rangée dans
/// Application Support/www (avec une copie des musiques et du logo). Elle est oubliée dès qu'une
/// nouvelle version de l'appli est installée (via AltStore), qui contient une page au moins aussi récente.
enum Updater {
    static let base = "https://jeu.cyberlogic.fr/"
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
        guard url.hasPrefix(base), var comps = URLComponents(string: url) else { return finish(false, "adresse refusée") }
        guard version.range(of: "^[0-9]+(\\.[0-9]+){0,3}$", options: .regularExpression) != nil else { return finish(false, "version invalide") }
        comps.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]
        var req = URLRequest(url: comps.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.setValue("BlueScreen-iOS", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let e = err { return finish(false, e.localizedDescription) }
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200, http.url?.host == "jeu.cyberlogic.fr",
                  let data = data, data.count > 100_000, data.count < 8_000_000,
                  let html = String(data: data, encoding: .utf8),
                  html.contains("const APP_VERSION = \"\(version)\""), html.contains("EBHost") else { return finish(false, "fichier inattendu") }
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
        }.resume()
    }
}
