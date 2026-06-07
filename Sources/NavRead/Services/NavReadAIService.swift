import CryptoKit
import Foundation
import Network

struct CodexAuthState: Equatable {
    var authenticated = false
    var pending = false
    var accountID = ""
    var statusMessage = "Codex not connected"
}

struct CodexBridgeSession: Equatable {
    var authenticated: Bool
    var accountID: String
    var email: String
    var expiresAt: Date?
    var model: String

    var statusMessage: String {
        guard authenticated else { return "Codex bridge is not connected" }
        if !email.isEmpty { return "Codex bridge connected: \(email)" }
        if !accountID.isEmpty { return "Codex bridge connected: \(accountID)" }
        return "Codex bridge connected"
    }
}

final class CodexBridgeClient: @unchecked Sendable {
    static let shared = CodexBridgeClient()

    private let apiBaseURL = URL(string: "http://127.0.0.1:1777")!
    private let callbackBaseURL = URL(string: "http://127.0.0.1:1455")!

    var signInURL: URL {
        apiBaseURL.appendingPathComponent("auth/start")
    }

    func session() async throws -> CodexBridgeSession {
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("health"))
        request.timeoutInterval = 1.5
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIError.message("Codex bridge is not available.")
        }
        let payload = try JSONDecoder().decode(HealthPayload.self, from: data)
        return CodexBridgeSession(
            authenticated: payload.authenticated ?? false,
            accountID: payload.accountId ?? "",
            email: payload.email ?? "",
            expiresAt: Self.date(from: payload.expiresAt),
            model: payload.model ?? ""
        )
    }

    func validatedSession() async throws -> CodexBridgeSession {
        let current = try await session()
        guard current.authenticated else { return current }
        do {
            try await validateChatAccess()
            return current
        } catch AIError.notAuthenticated {
            try? await logout()
            return CodexBridgeSession(authenticated: false, accountID: "", email: "", expiresAt: nil, model: current.model)
        } catch {
            throw error
        }
    }

    func logout() async throws {
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("auth/logout"))
        request.timeoutInterval = 2
        _ = try await URLSession.shared.data(for: request)
    }

    func completeCallback(_ value: String) async throws -> CodexBridgeSession {
        guard let callbackURL = Self.callbackURL(from: value, baseURL: callbackBaseURL) else {
            throw AIError.notAuthenticated
        }
        var request = URLRequest(url: callbackURL)
        request.timeoutInterval = 10
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIError.message("Codex bridge callback failed.")
        }
        let session = try await session()
        guard session.authenticated else {
            throw AIError.notAuthenticated
        }
        return session
    }

    func streamChat(
        systemPrompt: String,
        userPrompt: String,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws {
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "stream": true,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "text": ["verbosity": "medium"],
            "reasoning_effort": "medium"
        ])

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 401 {
                try? await logout()
                throw AIError.notAuthenticated
            }
            throw AIError.message("Codex bridge response failed with HTTP \(http.statusCode).")
        }

        var didStream = false
        var finalText = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let raw = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            if raw == "[DONE]" { break }
            guard let data = raw.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if let message = Self.errorMessage(from: object) {
                throw AIError.message(message)
            }
            guard let choices = object["choices"] as? [[String: Any]] else { continue }
            for choice in choices {
                if let delta = choice["delta"] as? [String: Any],
                   let content = delta["content"] as? String,
                   !content.isEmpty {
                    didStream = true
                    onDelta(content)
                } else if let message = choice["message"] as? [String: Any],
                          let content = message["content"] as? String {
                    finalText += content
                }
            }
        }

        if !didStream {
            let fallback = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty {
                onDelta(fallback)
            }
        }
    }

    private func validateChatAccess() async throws {
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "stream": false,
            "messages": [
                ["role": "system", "content": "Reply with exactly: ok"],
                ["role": "user", "content": "auth check"]
            ],
            "text": ["verbosity": "low"],
            "reasoning_effort": "low"
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.message("Codex bridge validation failed.")
        }
        if http.statusCode == 401 {
            throw AIError.notAuthenticated
        }
        if !(200..<300).contains(http.statusCode) {
            let message = Self.errorMessage(from: data) ?? "Codex bridge validation failed with HTTP \(http.statusCode)."
            if message.localizedCaseInsensitiveContains("token") && message.localizedCaseInsensitiveContains("invalid") {
                throw AIError.notAuthenticated
            }
            throw AIError.message(message)
        }
    }

    private static func callbackURL(from value: String, baseURL: URL) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           components.queryItems?.contains(where: { $0.name == "code" }) == true {
            var callback = URLComponents(url: baseURL.appendingPathComponent("auth/callback"), resolvingAgainstBaseURL: false)
            callback?.queryItems = components.queryItems
            return callback?.url
        }

        if trimmed.contains("code="),
           let components = URLComponents(string: "?\(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "?")))") {
            var callback = URLComponents(url: baseURL.appendingPathComponent("auth/callback"), resolvingAgainstBaseURL: false)
            callback?.queryItems = components.queryItems
            return callback?.url
        }

        return nil
    }

    private static func date(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func errorMessage(from payload: [String: Any]) -> String? {
        if let error = payload["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }
        return nil
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return errorMessage(from: object)
    }

    private struct HealthPayload: Decodable {
        var authenticated: Bool?
        var accountId: String?
        var email: String?
        var expiresAt: String?
        var model: String?
    }
}

actor CodexOAuthService {
    private let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    private let authorizeURL = URL(string: "https://auth.openai.com/oauth/authorize")!
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let redirectURI = "http://localhost:1455/auth/callback"
    private var callbackServer: LocalOAuthCallbackServer?

    func startLogin() async throws -> URL {
        let verifier = Self.randomURLSafe()
        let challenge = Self.challenge(for: verifier)
        let state = Self.randomURLSafe(bytes: 18)
        TokenVault.shared.pendingVerifier = verifier
        TokenVault.shared.pendingState = state
        try await startCallbackServer()

        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "openid profile email offline_access"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "prompt", value: "login"),
            URLQueryItem(name: "originator", value: "pi")
        ]
        guard let url = components?.url else {
            throw AIError.message("Could not create Codex authorization URL.")
        }
        return url
    }

    func completeManualCallback(_ value: String) async throws -> CodexCredentials {
        guard let parsed = Self.parseCodeAndState(value), let code = parsed.code else {
            throw AIError.notAuthenticated
        }
        if let state = parsed.state, !TokenVault.shared.pendingState.isEmpty, state != TokenVault.shared.pendingState {
            throw AIError.message("Codex OAuth state mismatch.")
        }
        return try await exchange(code: code, verifier: TokenVault.shared.pendingVerifier)
    }

    func validCredentials(skew: TimeInterval = 120) async throws -> CodexCredentials {
        guard let credentials = TokenVault.shared.load() else {
            throw AIError.notAuthenticated
        }
        if credentials.expiresAt > Date().addingTimeInterval(skew) {
            return credentials
        }
        guard !credentials.refresh.isEmpty else {
            TokenVault.shared.clear()
            throw AIError.notAuthenticated
        }
        return try await refresh(refreshToken: credentials.refresh, existingAccountID: credentials.accountID)
    }

    func refreshStoredCredentials() async throws -> CodexCredentials {
        guard let credentials = TokenVault.shared.load(), !credentials.refresh.isEmpty else {
            TokenVault.shared.clear()
            throw AIError.notAuthenticated
        }
        return try await refresh(refreshToken: credentials.refresh, existingAccountID: credentials.accountID)
    }

    private func startCallbackServer() async throws {
        callbackServer?.stop()
        let server = try LocalOAuthCallbackServer { code, state in
            await self.handleLocalCallback(code: code, state: state)
        }
        callbackServer = server
        do {
            try await server.waitUntilReady()
        } catch {
            server.stop()
            callbackServer = nil
            throw error
        }
    }

    private func handleLocalCallback(code: String, state: String?) async -> OAuthCallbackResult {
        do {
            if let state, !TokenVault.shared.pendingState.isEmpty, state != TokenVault.shared.pendingState {
                throw AIError.message("Codex OAuth state mismatch.")
            }
            let credentials = try await exchange(code: code, verifier: TokenVault.shared.pendingVerifier)
            callbackServer?.stop()
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .navReadCodexAuthCompleted,
                    object: nil,
                    userInfo: ["accountID": credentials.accountID]
                )
            }
            return OAuthCallbackResult(success: true, message: "Codex connected. You can return to NavRead.")
        } catch {
            let message = error.localizedDescription
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .navReadCodexAuthFailed,
                    object: nil,
                    userInfo: ["message": message]
                )
            }
            return OAuthCallbackResult(success: false, message: "Codex sign-in failed: \(message)")
        }
    }

    func exchange(code: String, verifier: String) async throws -> CodexCredentials {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI
        ]
        request.httpBody = formURLEncoded(body).data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.message(Self.oauthErrorMessage(from: data, statusCode: http.statusCode))
        }
        let payload: TokenResponse
        do {
            payload = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw AIError.message(Self.oauthErrorMessage(from: data, statusCode: nil))
        }
        let credentials = CodexCredentials(
            access: payload.accessToken,
            refresh: payload.refreshToken ?? "",
            expiresAt: Date().addingTimeInterval(TimeInterval(payload.expiresIn)),
            accountID: Self.accountID(from: payload.accessToken) ?? ""
        )
        try TokenVault.shared.save(credentials)
        return credentials
    }

    private func refresh(refreshToken: String, existingAccountID: String) async throws -> CodexCredentials {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncoded([
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken
        ]).data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = Self.oauthErrorMessage(from: data, statusCode: http.statusCode)
            if message.localizedCaseInsensitiveContains("invalid_grant") {
                TokenVault.shared.clear()
            }
            throw AIError.message(message)
        }
        let payload: TokenResponse
        do {
            payload = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw AIError.message(Self.oauthErrorMessage(from: data, statusCode: nil))
        }
        let credentials = CodexCredentials(
            access: payload.accessToken,
            refresh: payload.refreshToken ?? refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(payload.expiresIn)),
            accountID: Self.accountID(from: payload.accessToken) ?? existingAccountID
        )
        try TokenVault.shared.save(credentials)
        return credentials
    }

    private static func oauthErrorMessage(from data: Data, statusCode: Int?) -> String {
        let prefix = statusCode.map { "Codex OAuth token request failed with HTTP \($0)." } ?? "Codex OAuth token response was incomplete."
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return prefix
        }
        let detail = object["error_description"] as? String
            ?? object["error"] as? String
            ?? object["message"] as? String
        guard let detail, !detail.isEmpty else { return prefix }
        return "\(prefix) \(detail)"
    }

    private func formURLEncoded(_ values: [String: String]) -> String {
        values
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
            }
            .joined(separator: "&")
    }

    private static func randomURLSafe(bytes: Int = 32) -> String {
        let values = (0..<bytes).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
        let data = Data(values)
        return data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func parseCodeAndState(_ value: String) -> (code: String?, state: String?)? {
        if let url = URL(string: value), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            return (
                components.queryItems?.first(where: { $0.name == "code" })?.value,
                components.queryItems?.first(where: { $0.name == "state" })?.value
            )
        }
        if value.contains("code="), let components = URLComponents(string: "?\(value.trimmingCharacters(in: CharacterSet(charactersIn: "?")))") {
            return (
                components.queryItems?.first(where: { $0.name == "code" })?.value,
                components.queryItems?.first(where: { $0.name == "state" })?.value
            )
        }
        return (value, nil)
    }

    private static func accountID(from token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = json["https://api.openai.com/auth"] as? [String: Any],
              let account = auth["chatgpt_account_id"] as? String else { return nil }
        return account
    }
}

struct OAuthCallbackResult: Sendable {
    var success: Bool
    var message: String
}

private enum OAuthCallbackParseResult {
    case success(code: String, state: String?)
    case oauthError(String)
    case notCallback
}

final class LocalOAuthCallbackServer: @unchecked Sendable {
    typealias Handler = @Sendable (_ code: String, _ state: String?) async -> OAuthCallbackResult

    private let listener: NWListener
    private let queue = DispatchQueue(label: "NavRead.CodexOAuthCallback")
    private let handler: Handler
    private let readinessLock = NSLock()
    private var readiness: Readiness = .pending
    private var readinessWaiters: [CheckedContinuation<Void, Error>] = []

    init(port: UInt16 = 1455, handler: @escaping Handler) throws {
        self.handler = handler
        let parameters = NWParameters.tcp
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw AIError.message("Invalid OAuth callback port.")
        }
        listener = try NWListener(using: parameters, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.markReady()
            case .failed(let error):
                self?.markFailed(error)
            case .cancelled:
                self?.markFailed(AIError.message("OAuth callback server stopped before it was ready."))
            default:
                break
            }
        }
        listener.start(queue: queue)
    }

    func waitUntilReady() async throws {
        try await withCheckedThrowingContinuation { continuation in
            readinessLock.lock()
            switch readiness {
            case .ready:
                readinessLock.unlock()
                continuation.resume()
            case .failed(let error):
                readinessLock.unlock()
                continuation.resume(throwing: error)
            case .pending:
                readinessWaiters.append(continuation)
                readinessLock.unlock()
            }
        }
    }

    func stop() {
        listener.cancel()
    }

    private func markReady() {
        readinessLock.lock()
        guard case .pending = readiness else {
            readinessLock.unlock()
            return
        }
        readiness = .ready
        let waiters = readinessWaiters
        readinessWaiters = []
        readinessLock.unlock()
        waiters.forEach { $0.resume() }
    }

    private func markFailed(_ error: Error) {
        readinessLock.lock()
        guard case .pending = readiness else {
            readinessLock.unlock()
            return
        }
        readiness = .failed(error)
        let waiters = readinessWaiters
        readinessWaiters = []
        readinessLock.unlock()
        waiters.forEach { $0.resume(throwing: error) }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.send(status: 500, body: self.html(title: "NavRead Codex", message: error.localizedDescription, success: false), on: connection)
                return
            }
            let request = String(decoding: data ?? Data(), as: UTF8.self)
            switch self.parseCallback(from: request) {
            case .success(let code, let state):
                Task {
                    let result = await self.handler(code, state)
                    self.send(
                        status: result.success ? 200 : 500,
                        body: self.html(title: "NavRead Codex", message: result.message, success: result.success),
                        on: connection
                    )
                }
            case .oauthError(let message):
                self.stop()
                Task { @MainActor in
                    NotificationCenter.default.post(
                        name: .navReadCodexAuthFailed,
                        object: nil,
                        userInfo: ["message": message]
                    )
                }
                self.send(status: 400, body: self.html(title: "NavRead Codex", message: message, success: false), on: connection)
            case .notCallback:
                self.send(status: 404, body: self.html(title: "NavRead Codex", message: "Callback route not found.", success: false), on: connection)
            }
        }
    }

    private func parseCallback(from request: String) -> OAuthCallbackParseResult {
        guard let firstLine = request.components(separatedBy: "\r\n").first else { return .notCallback }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return .notCallback }
        let path = String(parts[1])
        guard let components = URLComponents(string: "http://localhost:1455\(path)"),
              components.path == "/auth/callback" else {
            return .notCallback
        }
        if let error = components.queryItems?.first(where: { $0.name == "error_description" })?.value
            ?? components.queryItems?.first(where: { $0.name == "error" })?.value {
            return .oauthError("Codex sign-in failed: \(error)")
        }
        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            return .oauthError("Codex sign-in did not return an authorization code.")
        }
        let state = components.queryItems?.first(where: { $0.name == "state" })?.value
        return .success(code: code, state: state)
    }

    private func send(status: Int, body: String, on connection: NWConnection) {
        let reason = status == 200 ? "OK" : status == 400 ? "Bad Request" : status == 404 ? "Not Found" : "Internal Server Error"
        let data = Data(body.utf8)
        let response = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(data.count)\r
        Connection: close\r
        \r

        """
        var payload = Data(response.utf8)
        payload.append(data)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func html(title: String, message: String, success: Bool) -> String {
        let escapedMessage = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let color = success ? "#8BE28B" : "#FF9A8A"
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <title>\(title)</title>
          <style>
            body{margin:0;min-height:100vh;display:grid;place-items:center;background:#111;color:#f4f1ea;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif}
            main{width:min(560px,calc(100vw - 48px));padding:34px;border:1px solid rgba(255,255,255,.16);border-radius:24px;background:rgba(255,255,255,.08);box-shadow:0 24px 80px rgba(0,0,0,.35)}
            h1{margin:0 0 10px;font-family:Georgia,serif;font-size:34px}
            p{margin:0;color:#c8c3b8;line-height:1.5}
            .dot{width:12px;height:12px;border-radius:999px;background:\(color);box-shadow:0 0 24px \(color);display:inline-block;margin-right:10px}
          </style>
        </head>
        <body><main><h1><span class="dot"></span>NavRead Codex</h1><p>\(escapedMessage)</p></main></body>
        </html>
        """
    }
}

private enum Readiness {
    case pending
    case ready
    case failed(Error)
}

actor NavReadAIService {
    nonisolated let model = "gpt-5.4"
    private static let responseURL = URL(string: "https://chatgpt.com/backend-api/codex/responses")!

    func chapterDrafts(for metadata: BookMetadata, authenticated: Bool) async -> [ChapterDraft] {
        if authenticated, let generated = try? await codexChapters(for: metadata), !generated.isEmpty {
            return generated
        }
        return offlineChapters(for: metadata)
    }

    func quoteCandidates(from text: String, chapters: [Chapter]) async -> [QuoteCandidate] {
        if let generated = try? await codexQuoteCandidates(from: text, chapters: chapters),
           !generated.isEmpty {
            return generated
        }
        let sentences = text
            .components(separatedBy: CharacterSet(charactersIn: "\n.?!"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 36 }
            .prefix(8)

        return sentences.map { sentence in
            QuoteCandidate(
                text: sentence,
                cleanedText: sentence,
                suggestedChapterID: chapters.first?.id,
                pageLocator: "",
                kind: classifyKind(sentence),
                tags: suggestedTags(for: sentence),
                note: "Classified and extracted from source text.",
                confidence: 0.72
            )
        }
    }

    func savedQuoteCandidates(from text: String, preferCodex: Bool = true) async -> [SavedQuoteCandidate] {
        let cleaned = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24_000))
        guard !cleaned.isEmpty else { return [] }
        if preferCodex,
           let generated = try? await codexSavedQuoteCandidates(from: cleaned),
           !generated.isEmpty {
            return generated
        }
        return offlineSavedQuoteCandidates(from: cleaned)
    }

    func chatReply(prompt: String, context: String, conversationHistory: String = "") async -> String {
        let systemPrompt = Self.chatSystemPrompt
        let userPrompt = Self.chatUserPrompt(context: context, conversationHistory: conversationHistory, prompt: prompt)
        if let reply = try? await codexText(systemPrompt: systemPrompt, userPrompt: userPrompt), !reply.isEmpty {
            return reply
        }
        return "Codex could not return a response. Check sign-in and network state."
    }

    nonisolated func chatReplyStream(prompt: String, context: String, conversationHistory: String = "") -> AsyncThrowingStream<String, Error> {
        return codexTextStream(
            systemPrompt: Self.chatSystemPrompt,
            userPrompt: Self.chatUserPrompt(context: context, conversationHistory: conversationHistory, prompt: prompt)
        )
    }

    private func codexChapters(for metadata: BookMetadata) async throws -> [ChapterDraft] {
        let systemPrompt = "You create editable chapter scaffolds for NavRead. Return only valid JSON."
        let userPrompt = """
        Create a plausible editable chapter scaffold for this book.

        Title: \(metadata.title)
        Author: \(metadata.author)
        ISBN: \(metadata.isbn)
        Summary: \(metadata.summary)

        Return JSON:
        {
          "chapters": [
            {"title": "Chapter title", "summary": "Short user-facing context", "page_start": null, "page_end": null}
          ]
        }
        Use 8-16 chapters. If unsure, make a conservative scaffold and mention uncertainty in summaries.
        """
        let raw = try await codexText(systemPrompt: systemPrompt, userPrompt: userPrompt)
        return decodeChapterDrafts(raw)
    }

    private func codexQuoteCandidates(from text: String, chapters: [Chapter]) async throws -> [QuoteCandidate] {
        let chapterGuide = chapters.enumerated()
            .map { "\($0.offset): \($0.element.title) - \($0.element.summary)" }
            .joined(separator: "\n")
        let systemPrompt = "You classify and extract reading captures for NavRead. Return only valid JSON. Preserve exact source text in text; clean OCR only in cleaned_text."
        let userPrompt = """
        Extract the best quote candidates from this captured source. Classify each candidate as one of:
        quote, passage, idea, note, question, code.
        Assign chapter_index when plausible.

        Chapters:
        \(chapterGuide)

        Source:
        \(text.prefix(6000))

        Return JSON:
        {
          "quotes": [
            {
              "text": "raw exact candidate",
              "cleaned_text": "cleaned candidate",
              "chapter_index": 0,
              "page_locator": "",
              "kind": "quote",
              "tags": ["tag"],
              "note": "short context",
              "confidence": 0.0
            }
          ]
        }
        """
        let raw = try await codexText(systemPrompt: systemPrompt, userPrompt: userPrompt)
        return decodeQuoteCandidates(raw, chapters: chapters)
    }

    private func codexSavedQuoteCandidates(from text: String) async throws -> [SavedQuoteCandidate] {
        let systemPrompt = "You parse bulk standalone quotes for NavRead. Return only valid JSON. Do not invent quote text."
        let userPrompt = """
        Parse this bulk quote paste into standalone quotes.

        Rules:
        - Preserve the quote wording exactly in text, except trimming quote marks and whitespace.
        - Extract author/person when present.
        - Extract source/book/link/context when present.
        - Create concise tags and a short useful note.
        - Skip empty lines, headings, duplicate repeats, and non-quote filler.
        - If author or source is unknown, use an empty string.

        Paste:
        \(text.prefix(24_000))

        Return JSON:
        {
          "quotes": [
            {
              "text": "quote text",
              "author": "author or person",
              "source": "source/book/link/context",
              "note": "short note",
              "tags": ["tag"],
              "confidence": 0.0
            }
          ]
        }
        """
        let raw = try await codexText(systemPrompt: systemPrompt, userPrompt: userPrompt)
        return decodeSavedQuoteCandidates(raw)
    }

    private static let chatSystemPrompt = """
    You are NavRead AI, a concise reading, research, and quote assistant inside a macOS reading library.
    Use the provided NavRead context first. If the user asks for general literary or technical help, clearly separate library-backed facts from general reasoning.
    Capabilities:
    - Explain passages, quotes, ideas, notes, chapters, and author intent.
    - Extract useful quote candidates from pasted text.
    - Clean OCR while preserving meaning.
    - Classify captured material as quote, passage, idea, note, question, or code.
    - Suggest tags, notes, chapter placement, and related quotes.
    Output rules:
    - Use short display-friendly Markdown: brief headings, bullets, numbered steps, and fenced code only for actual code.
    - Do not output JSON unless the user explicitly asks for it.
    - Keep answers compact and useful. State uncertainty plainly.
    """

    private static func chatUserPrompt(context: String, conversationHistory: String, prompt: String) -> String {
        """
        NavRead context:
        \(context)

        Conversation so far:
        \(conversationHistory.isEmpty ? "None." : conversationHistory)

        User request:
        \(prompt)
        """
    }

    private func codexText(systemPrompt: String, userPrompt: String) async throws -> String {
        var text = ""
        for try await delta in codexTextStream(systemPrompt: systemPrompt, userPrompt: userPrompt) {
            text += delta
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func codexTextStream(systemPrompt: String, userPrompt: String) -> AsyncThrowingStream<String, Error> {
        let responseURL = Self.responseURL
        let modelName = model
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    if let bridgeSession = try? await CodexBridgeClient.shared.session(),
                       bridgeSession.authenticated {
                        do {
                            try await CodexBridgeClient.shared.streamChat(
                                systemPrompt: systemPrompt,
                                userPrompt: userPrompt,
                                onDelta: { continuation.yield($0) }
                            )
                            continuation.finish()
                            return
                        } catch {
                            if TokenVault.shared.load() == nil {
                                throw error
                            }
                            // Fall through to the legacy direct-token path if NavRead also has tokens.
                        }
                    }

                    let oauth = CodexOAuthService()
                    var credentials = try await oauth.validCredentials()
                    var didRetryAfterUnauthorized = false

                    retryLoop: while true {
                        var request = URLRequest(url: responseURL)
                        request.httpMethod = "POST"
                        request.setValue("Bearer \(credentials.access)", forHTTPHeaderField: "Authorization")
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
                        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
                        request.setValue("pi", forHTTPHeaderField: "originator")
                        if !credentials.accountID.isEmpty {
                            request.setValue(credentials.accountID, forHTTPHeaderField: "chatgpt-account-id")
                        }
                        let body: [String: Any] = [
                            "model": modelName,
                            "store": false,
                            "stream": true,
                            "instructions": systemPrompt,
                            "input": [["role": "user", "content": userPrompt]],
                            "text": ["verbosity": "medium"],
                            "include": ["reasoning.encrypted_content"],
                            "tool_choice": "auto",
                            "parallel_tool_calls": true,
                            "reasoning": ["effort": "medium", "summary": "auto"]
                        ]
                        request.httpBody = try JSONSerialization.data(withJSONObject: body)
                        let (bytes, response) = try await URLSession.shared.bytes(for: request)
                        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                            if http.statusCode == 401, !didRetryAfterUnauthorized {
                                didRetryAfterUnauthorized = true
                                credentials = try await oauth.refreshStoredCredentials()
                                continue retryLoop
                            }
                            throw AIError.message("Codex response failed with HTTP \(http.statusCode).")
                        }

                        var didStream = false
                        var finalText = ""
                        for try await line in bytes.lines {
                            guard line.hasPrefix("data:") else { continue }
                            let raw = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                            if raw == "[DONE]" { break }
                            guard let data = raw.data(using: .utf8),
                                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                                continue
                            }
                            let type = event["type"] as? String
                            if type == "response.output_text.delta", let delta = event["delta"] as? String {
                                didStream = true
                                continuation.yield(delta)
                            } else if type == "response.completed", let response = event["response"] as? [String: Any] {
                                finalText = Self.extractText(from: response)
                            } else if type == "response.failed" || type == "response.incomplete" {
                                throw AIError.message(Self.extractErrorMessage(from: event) ?? "Codex response did not complete.")
                            } else if type == "error" {
                                throw AIError.message(Self.extractErrorMessage(from: event) ?? "Codex response error.")
                            }
                        }
                        if !didStream {
                            let fallback = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !fallback.isEmpty {
                                continuation.yield(fallback)
                            }
                        }
                        continuation.finish()
                        break retryLoop
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func offlineChapters(for metadata: BookMetadata) -> [ChapterDraft] {
        let base = [
            "Opening Frame",
            "Central Tension",
            "First Turn",
            "Deepening Argument",
            "Key Evidence",
            "Counterpoint",
            "Inner Weather",
            "Practical Consequence",
            "Late Revelation",
            "Synthesis",
            "Closing Movement",
            "Afterglow Notes"
        ]
        return base.enumerated().map { index, title in
            ChapterDraft(
                title: title,
                summary: "AI draft chapter \(index + 1) for \(metadata.title). Edit once source structure is known.",
                pageStart: nil,
                pageEnd: nil
            )
        }
    }

    private func decodeChapterDrafts(_ raw: String) -> [ChapterDraft] {
        guard let object = extractJSONObject(raw),
              let chapters = object["chapters"] as? [[String: Any]] else { return [] }
        return chapters.compactMap { item in
            guard let title = item["title"] as? String, !title.isEmpty else { return nil }
            return ChapterDraft(
                title: title,
                summary: (item["summary"] as? String) ?? "",
                pageStart: item["page_start"] as? Int,
                pageEnd: item["page_end"] as? Int
            )
        }
    }

    private func decodeQuoteCandidates(_ raw: String, chapters: [Chapter]) -> [QuoteCandidate] {
        guard let object = extractJSONObject(raw),
              let quotes = object["quotes"] as? [[String: Any]] else { return [] }
        return quotes.compactMap { item in
            guard let text = item["text"] as? String, !text.isEmpty else { return nil }
            let chapterIndex = item["chapter_index"] as? Int
            let tags = (item["tags"] as? [String]) ?? []
            let kind = CapturedContentKind(rawValue: (item["kind"] as? String) ?? "") ?? classifyKind(text)
            return QuoteCandidate(
                text: text,
                cleanedText: (item["cleaned_text"] as? String) ?? text,
                suggestedChapterID: chapterIndex.flatMap { chapters.indices.contains($0) ? chapters[$0].id : nil },
                pageLocator: (item["page_locator"] as? String) ?? "",
                kind: kind,
                tags: tags.includingClassification(kind),
                note: (item["note"] as? String) ?? "",
                confidence: (item["confidence"] as? Double) ?? 0.7
            )
        }
    }

    private func decodeSavedQuoteCandidates(_ raw: String) -> [SavedQuoteCandidate] {
        guard let object = extractJSONObject(raw),
              let quotes = object["quotes"] as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        return quotes.compactMap { item in
            guard let text = (item["text"] as? String)?.cleanedQuoteText, !text.isEmpty else { return nil }
            let key = text.normalizedQuoteKey
            guard seen.insert(key).inserted else { return nil }
            return SavedQuoteCandidate(
                text: text,
                author: ((item["author"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                source: ((item["source"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                note: ((item["note"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                tags: ((item["tags"] as? [String]) ?? suggestedTags(for: text)).normalizedTags(),
                confidence: (item["confidence"] as? Double) ?? 0.75
            )
        }
    }

    private func offlineSavedQuoteCandidates(from text: String) -> [SavedQuoteCandidate] {
        var candidates: [SavedQuoteCandidate] = []
        var seen = Set<String>()
        for block in quoteBlocks(from: text).prefix(120) {
            guard let parsed = parseStandaloneQuote(block), !parsed.text.isEmpty else { continue }
            let key = parsed.text.normalizedQuoteKey
            guard seen.insert(key).inserted else { continue }
            candidates.append(
                SavedQuoteCandidate(
                    text: parsed.text,
                    author: parsed.author,
                    source: parsed.source,
                    note: parsed.source.isEmpty ? "Bulk imported quote." : "Bulk imported from \(parsed.source).",
                    tags: suggestedTags(for: parsed.text).normalizedTags(),
                    confidence: parsed.author.isEmpty ? 0.62 : 0.76
                )
            )
        }
        return candidates
    }

    private func quoteBlocks(from text: String) -> [String] {
        let blankSeparated = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if blankSeparated.count > 1 {
            return blankSeparated
        }
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 8 }
    }

    private func parseStandaloneQuote(_ block: String) -> (text: String, author: String, source: String)? {
        var cleaned = block
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "\n", with: " ")
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }

        let separators = [" — ", " – ", " - ", " -- "]
        for separator in separators {
            if let range = cleaned.range(of: separator, options: .backwards) {
                let quote = String(cleaned[..<range.lowerBound]).cleanedQuoteText
                let attribution = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard quote.count > 8 else { continue }
                let parts = attribution.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                return (quote, parts.first ?? "", parts.dropFirst().joined(separator: ", "))
            }
        }

        if cleaned.hasPrefix("\""), let closing = cleaned.dropFirst().firstIndex(of: "\"") {
            let quote = String(cleaned[cleaned.index(after: cleaned.startIndex)..<closing]).cleanedQuoteText
            let rest = String(cleaned[cleaned.index(after: closing)...]).trimmingCharacters(in: CharacterSet(charactersIn: " -—–,"))
            guard quote.count > 8 else { return nil }
            return (quote, rest, "")
        }

        let quote = cleaned.cleanedQuoteText
        return quote.count > 8 ? (quote, "", "") : nil
    }

    private func extractJSONObject(_ raw: String) -> [String: Any]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            trimmed,
            fencedJSON(trimmed),
            substringJSON(trimmed)
        ].compactMap { $0 }
        for candidate in candidates {
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            return object
        }
        return nil
    }

    private func fencedJSON(_ raw: String) -> String? {
        guard let start = raw.range(of: "```json"),
              let end = raw[start.upperBound...].range(of: "```") else { return nil }
        return String(raw[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func substringJSON(_ raw: String) -> String? {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") else { return nil }
        return String(raw[start...end])
    }

    private static func extractText(from payload: [String: Any]) -> String {
        var candidates: [String] = []
        if let output = payload["output"] as? [[String: Any]] {
            for item in output {
                if let content = item["content"] as? [[String: Any]] {
                    candidates += content.compactMap { $0["text"] as? String }
                }
            }
        }
        if let content = payload["content"] as? [[String: Any]] {
            candidates += content.compactMap { $0["text"] as? String }
        }
        return candidates.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func extractErrorMessage(from payload: [String: Any]) -> String? {
        if let message = payload["message"] as? String, !message.isEmpty {
            return message
        }
        if let error = payload["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }
        if let response = payload["response"] as? [String: Any],
           let error = response["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }
        return nil
    }

    private func suggestedTags(for text: String) -> [String] {
        let lower = text.lowercased()
        var tags: [String] = []
        if lower.contains("memory") { tags.append("memory") }
        if lower.contains("work") { tags.append("work") }
        if lower.contains("love") { tags.append("love") }
        if lower.contains("time") { tags.append("time") }
        if lower.contains("art") || lower.contains("create") { tags.append("creation") }
        return tags.isEmpty ? ["quote"] : tags
    }
}

private func classifyKind(_ text: String) -> CapturedContentKind {
    let lowered = text.lowercased()
    let codeMarkers = ["func ", "let ", "var ", "const ", "class ", "struct ", "import ", "return ", "{", "};", "```", "=>", "def "]
    if codeMarkers.contains(where: { lowered.contains($0) }) {
        return .code
    }
    if lowered.hasSuffix("?") || lowered.contains("why ") || lowered.contains("how ") {
        return .question
    }
    if text.count > 280 {
        return .passage
    }
    return .quote
}

private extension String {
    var cleanedQuoteText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedQuoteKey: String {
        lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension [String] {
    func includingClassification(_ kind: CapturedContentKind) -> [String] {
        let classification = "type-\(kind.rawValue)"
        return contains(where: { $0.caseInsensitiveCompare(classification) == .orderedSame }) ? self : self + [classification]
    }
}

enum AIError: Error, LocalizedError {
    case notAuthenticated
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Codex OAuth is not connected."
        case .message(let value):
            value
        }
    }
}

struct CodexCredentials: Codable {
    var access: String
    var refresh: String
    var expiresAt: Date
    var accountID: String
}

private struct TokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

final class TokenVault: @unchecked Sendable {
    static let shared = TokenVault()
    private let lock = NSLock()
    private var storedPendingVerifier = ""
    private var storedPendingState = ""

    var pendingVerifier: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedPendingVerifier
        }
        set {
            lock.lock()
            storedPendingVerifier = newValue
            lock.unlock()
        }
    }

    var pendingState: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedPendingState
        }
        set {
            lock.lock()
            storedPendingState = newValue
            lock.unlock()
        }
    }

    private var tokenURL: URL {
        LibraryPaths.root.appendingPathComponent("codex_tokens.json")
    }

    func load() -> CodexCredentials? {
        guard let data = try? Data(contentsOf: tokenURL) else { return nil }
        return try? JSONDecoder().decode(CodexCredentials.self, from: data)
    }

    func save(_ credentials: CodexCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        try LibraryPaths.ensure()
        try data.write(to: tokenURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
    }

    func clear() {
        try? FileManager.default.removeItem(at: tokenURL)
    }
}
