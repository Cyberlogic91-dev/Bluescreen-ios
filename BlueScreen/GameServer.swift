import Foundation
import Network

/// Serveur HTTP minimal pour le mode Wi-Fi (aucune dépendance, aucun cloud) — portage de GameServer.java.
///   GET  /            -> la page du jeu (mode invité)
///   POST /join        -> corps = prénom ; renvoie {"pid": "..."}
///   GET  /poll?pid&v  -> attend (jusqu'à 20 s) une vue plus récente que v
///   POST /act?pid     -> corps = action JSON, transmise au moteur de la page de l'hôte
final class GameServer {
    private let indexURL: URL
    private let callJs: (String) -> Void
    private var listener: NWListener?
    private let q = DispatchQueue(label: "fr.cyberlogic.bluescreen.server")
    private(set) var port: UInt16 = 8642

    // état partagé (uniquement sur la file `q`)
    private var views: [String: String?] = [:]
    private var versions: [String: Int64] = [:]
    private var clock: Int64 = 0
    private var waiting: [String: [(conn: NWConnection, v: Int64)]] = [:]

    init(indexURL: URL, callJs: @escaping (String) -> Void) {
        self.indexURL = indexURL
        self.callJs = callJs
    }

    enum Failure: LocalizedError { case noPort; var errorDescription: String? { "aucun port libre" } }

    func start() throws {
        guard let p = (8642...8649).first(where: Self.portIsFree) else { throw Failure.noPort }
        port = UInt16(p)
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.start(queue: q)
        listener = l
    }

    func stop() {
        q.async {
            self.listener?.cancel(); self.listener = nil
            for list in self.waiting.values { for w in list { w.conn.cancel() } }
            self.waiting.removeAll(); self.views.removeAll(); self.versions.removeAll()
        }
    }

    /// Nouvelle vue pour un joueur : réveille ses requêtes /poll en attente.
    func publish(pid: String, json: String) {
        q.async {
            self.clock += 1
            self.views[pid] = json
            self.versions[pid] = self.clock
            let list = self.waiting.removeValue(forKey: pid) ?? []
            for w in list { self.answerPoll(w.conn, pid: pid) }
        }
    }

    // MARK: - Connexions

    private func accept(_ c: NWConnection) {
        c.start(queue: q)
        receiveRequest(c, buffer: Data())
    }

    private func receiveRequest(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self = self else { return }
            var buf = buffer
            if let d = data { buf.append(d) }
            if err != nil || buf.count > 140_000 { c.cancel(); return }
            guard let headEnd = buf.range(of: Data("\r\n\r\n".utf8)) else {
                if done { c.cancel() } else { self.receiveRequest(c, buffer: buf) }
                return
            }
            let head = String(data: buf[..<headEnd.lowerBound], encoding: .utf8) ?? ""
            var len = 0
            for line in head.components(separatedBy: "\r\n") {
                let kv = line.split(separator: ":", maxSplits: 1)
                if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                    len = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
                }
            }
            if len < 0 || len > 65536 { len = 0 }
            let body = buf[headEnd.upperBound...]
            if body.count < len && !done { self.receiveRequest(c, buffer: buf); return }
            self.route(c, head: head, body: String(data: body.prefix(len), encoding: .utf8) ?? "")
        }
    }

    private func route(_ c: NWConnection, head: String, body: String) {
        let first = head.components(separatedBy: "\r\n").first ?? ""
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { c.cancel(); return }
        let method = String(parts[0]), target = String(parts[1])
        let comps = URLComponents(string: "http://h" + target)
        let path = comps?.path ?? "/"
        func param(_ k: String) -> String? { comps?.queryItems?.first { $0.name == k }?.value }

        switch (method, path) {
        case ("GET", "/"), ("GET", "/index.html"):
            let data = (try? Data(contentsOf: indexURL)) ?? Data()
            send(c, 200, "text/html; charset=utf-8", data)
        case ("POST", "/join"):
            let pid = Self.newPid()
            views[pid] = .some(nil); versions[pid] = 0
            callJs("window.EBNet&&EBNet.onJoin(\(JS.quote(pid)),\(JS.quote(body)))")
            sendJSON(c, "{\"pid\":\(JS.quote(pid))}")
        case ("GET", "/poll"):
            let pid = param("pid") ?? "", v = Int64(param("v") ?? "0") ?? 0
            guard let cur = versions[pid] else { sendJSON(c, "{\"unknown\":true}"); return }
            if cur > v { answerPoll(c, pid: pid); return }
            // attente longue : réponse dès la prochaine vue, ou au bout de 20 s
            waiting[pid, default: []].append((conn: c, v: v))
            q.asyncAfter(deadline: .now() + 20) { [weak self] in
                guard let self = self, var list = self.waiting[pid], let i = list.firstIndex(where: { $0.conn === c }) else { return }
                list.remove(at: i); self.waiting[pid] = list.isEmpty ? nil : list
                self.answerPoll(c, pid: pid)
            }
        case ("POST", "/act"):
            let pid = param("pid") ?? ""
            let known = versions[pid] != nil
            if known { callJs("window.EBNet&&EBNet.onAction(\(JS.quote(pid)),\(JS.quote(body)))") }
            sendJSON(c, known ? "{\"ok\":true}" : "{\"unknown\":true}")
        default:
            send(c, 404, "text/plain; charset=utf-8", Data("Introuvable".utf8))
        }
    }

    private func answerPoll(_ c: NWConnection, pid: String) {
        guard let v = versions[pid] else { sendJSON(c, "{\"unknown\":true}"); return }
        let view = views[pid] ?? nil
        sendJSON(c, "{\"v\":\(v),\"view\":\(view.map { JS.quote($0) } ?? "null")}")
    }

    private func sendJSON(_ c: NWConnection, _ json: String) { send(c, 200, "application/json; charset=utf-8", Data(json.utf8)) }

    private func send(_ c: NWConnection, _ code: Int, _ type: String, _ data: Data) {
        var out = Data(("HTTP/1.1 \(code) \(code == 200 ? "OK" : "Not Found")\r\n"
            + "Content-Type: \(type)\r\nContent-Length: \(data.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n").utf8)
        out.append(data)
        c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
    }

    // MARK: - Outils

    private static func newPid() -> String {
        var b = [UInt8](repeating: 0, count: 9)
        _ = SecRandomCopyBytes(kSecRandomDefault, b.count, &b)
        return b.map { String(format: "%02x", $0) }.joined()
    }

    /// Vérifie qu'un port TCP est libre (bind test) avant d'ouvrir l'écoute.
    private static func portIsFree(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr = in_addr(s_addr: 0)
        let r = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        return r == 0
    }
}
