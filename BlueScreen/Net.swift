import Foundation

/// Réseau : appels de la connexion Discord (OAuth 2 + PKCE, sans serveur ni secret) et adresse Wi-Fi locale.
enum Net {
    /// POST x-www-form-urlencoded ou GET avec jeton Bearer ; renvoie le corps JSON ou {"error": "..."}.
    static func request(method: String, url: String, body: String?, bearer: String?, completion: @escaping (String?) -> Void) {
        guard let u = URL(string: url), u.scheme == "https" else { completion("{\"error\":\"adresse invalide\"}"); return }
        var r = URLRequest(url: u, timeoutInterval: 15)
        r.httpMethod = method
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("BlueScreen-iOS/1.0", forHTTPHeaderField: "User-Agent")
        if let b = bearer { r.setValue("Bearer \(b)", forHTTPHeaderField: "Authorization") }
        if let body = body {
            r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            r.httpBody = Data(body.utf8)
        }
        URLSession.shared.dataTask(with: r) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let s = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            DispatchQueue.main.async {
                if let e = err { completion("{\"error\":\(JS.quote(e.localizedDescription))}") }
                else if code >= 400 { completion("{\"error\":\"HTTP \(code)\",\"detail\":\(JS.quote(s))}") }
                else { completion(s) }
            }
        }.resume()
    }

    /// Télécharge une image (avatar Discord) et la renvoie en data URL (300 Ko maximum).
    static func imageDataURL(_ url: String, completion: @escaping (String?) -> Void) {
        guard let u = URL(string: url), u.scheme == "https" else { completion(""); return }
        URLSession.shared.dataTask(with: URLRequest(url: u, timeoutInterval: 15)) { data, resp, _ in
            var out = ""
            if let d = data, d.count <= 300 * 1024 {
                var type = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "image/png"
                type = String(type.split(separator: ";").first ?? "image/png")
                if !type.hasPrefix("image/") { type = "image/png" }
                out = "data:\(type);base64," + d.base64EncodedString()
            }
            DispatchQueue.main.async { completion(out) }
        }.resume()
    }

    /// Adresse IPv4 de l'iPhone sur le Wi-Fi (en0) ou en partage de connexion (bridge100).
    static func localIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var found: [String: String] = [:]
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            let ifa = cur.pointee
            if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: ifa.ifa_name)
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    found[name] = String(cString: host)
                }
            }
            p = ifa.ifa_next
        }
        return found["en0"] ?? found["bridge100"] ?? found.first { $0.key.hasPrefix("en") || $0.key.hasPrefix("bridge") }?.value
    }
}
