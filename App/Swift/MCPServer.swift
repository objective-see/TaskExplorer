//
//  MCPServer.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: DEBUG BUILDS ONLY: a minimal MCP server (streamable HTTP transport, JSON-RPC 2.0) bound to localhost, used to
//        drive the app for automated testing (select processes, set filters, query the model). Not compiled into
//        release builds: the app never listens on anything, and there is no token to protect.
//        enable (debug builds) with: defaults write com.objective-see.taskexplorer mcpEnabled -bool true
//        the bearer token is in the same defaults domain (key 'mcpToken'); the port (7373) via 'mcpPort'

#if DEBUG

import Foundation
import Network
import Security
import os

final class MCPServer {

    //shared
    static let shared = MCPServer()

    //listener
    private var listener: NWListener?

    //queue
    private let queue = DispatchQueue(label: "com.objective-see.taskexplorer.mcp")

    //log
    private let log = Logger(subsystem: "com.objective-see.taskexplorer", category: "mcp")

    //running?
    var isRunning: Bool { listener != nil }

    //last (fatal) error, e.g. the port is taken (another local user could bind it first and harvest the token)
    // ->shown in Settings; nil when running
    @Published private(set) var lastError: String?

    //max concurrent connections (unauthenticated clients could otherwise open thousands, each holding buffers)
    // ->and connections that never complete a request are dropped after a few seconds (see 'scheduleIdleCheck'), so a
    //   local process holding sockets open can't lock out real clients for long
    private let maxConnections = 128

    //max size of the request head (before the blank line)
    private let maxHeadBytes = 16 * 1024

    //port
    private(set) var port: Int = 0

    //bearer token (prefs)
    // ->required on every request: other users' processes, sandboxed apps, or a page served from localhost can otherwise
    //   reach the server, and the data (root-level process/file/connection info) is more than they could get on their own
    private(set) var token: String = ""

    //per-connection state (for idle timeouts)
    private final class ConnectionState { var lastActivity = Date(); var requests = 0 }
    private var states: [ObjectIdentifier: ConnectionState] = [:]

    //load (or create) the bearer token
    @discardableResult static func loadOrCreateToken() -> String {
        if let existing = UserDefaults.standard.string(forKey: PREF_MCP_TOKEN), !existing.isEmpty { shared.queue.sync { shared.token = existing }; return existing }
        return regenerateToken()
    }

    //(re)generate the bearer token
    @discardableResult static func regenerateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess { arc4random_buf(&bytes, bytes.count) }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: PREF_MCP_TOKEN)
        shared.queue.sync { shared.token = token }
        return token
    }

    //start (if enabled)
    func startIfEnabled() {
        if getPreferenceBool(PREF_MCP_ENABLED) { start() }
    }

    //start
    func start() {
        guard listener == nil else { return }
        let port = mcpServerPort()
        _ = MCPServer.loadOrCreateToken()
        lastError = nil
        do {
            let params = NWParameters.tcp
            //note: no local endpoint reuse; with it, another same-uid process could also bind the port and receive requests
            //bind to loopback only (never reachable from the network)
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(port))!)
            let listener = try NWListener(using: params)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.log.info("MCP server listening on 127.0.0.1:\(port)")
                case .failed(let error):
                    self?.log.error("MCP server failed: \(error.localizedDescription)")
                    //tell the user (Settings): the port may be taken by another process, which then receives clients' tokens
                    DispatchQueue.main.async {
                        self?.lastError = "The MCP server could not listen on port \(port) (\(error.localizedDescription)). If another program owns the port, pick a different one and regenerate the token."
                        self?.stop()
                    }
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
            self.listener = listener
            self.port = port
        } catch {
            log.error("failed to create MCP listener: \(error.localizedDescription)")
            lastError = "The MCP server could not start: \(error.localizedDescription)"
        }
    }

    //stop
    func stop() {
        listener?.cancel()
        listener = nil
    }

    /* HTTP */

    //accept connection & read request(s)
    private func accept(_ connection: NWConnection) {
        //note: listener is bound to 127.0.0.1, so only local clients can connect
        //too many? refuse (each open connection holds buffers until its request completes or the 30s idle timeout)
        guard states.count < maxConnections else {
            log.error("MCP: refusing connection (\(self.states.count) already open)")
            connection.cancel()
            return
        }
        let state = ConnectionState()
        states[ObjectIdentifier(connection)] = state
        let key = ObjectIdentifier(connection)
        connection.stateUpdateHandler = { [weak self, weak connection] newState in
            switch newState {
            case .cancelled, .failed:
                self?.states[key] = nil
                connection?.stateUpdateHandler = nil
            default: break
            }
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
        scheduleIdleCheck(connection)
    }

    //idle timeout
    // ->5s for a connection that has yet to complete a request (half-open / slowloris), 30s between keep-alive requests
    private func scheduleIdleCheck(_ connection: NWConnection) {
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, let state = self.states[ObjectIdentifier(connection)] else { return }
            let limit: TimeInterval = (state.requests == 0) ? 5 : 30
            if Date().timeIntervalSince(state.lastActivity) >= limit { connection.cancel() } else { self.scheduleIdleCheck(connection) }
        }
    }

    //read (until full request), then handle
    private func receive(on connection: NWConnection, buffer: Data) {
        //a complete (pipelined) request already buffered? handle it without reading more
        if !buffer.isEmpty, HTTPRequest.parse(buffer).request != nil {
            process(buffer: buffer, isComplete: false, on: connection)
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if error != nil || (isComplete && buffer.isEmpty) { connection.cancel(); return }
            self.process(buffer: buffer, isComplete: isComplete, on: connection)
        }
    }

    //parse & dispatch what's buffered (or read more)
    private func process(buffer: Data, isComplete: Bool, on connection: NWConnection) {
        let parsed = HTTPRequest.parse(buffer)
        if parsed.malformed {
            send(HTTPResponse(status: 400, body: Data("bad request".utf8), contentType: "text/plain"), on: connection, keepAlive: false)
        } else if let request = parsed.request {
            states[ObjectIdentifier(connection)]?.lastActivity = Date()
            states[ObjectIdentifier(connection)]?.requests += 1
            //anything pipelined after this request is kept for the next round
            let leftover = buffer.count > parsed.consumed ? Data(buffer[(buffer.startIndex + parsed.consumed)...]) : Data()
            handle(request, on: connection, leftover: leftover)
        } else if buffer.count > (1 << 20) || (buffer.count > maxHeadBytes && buffer.range(of: Data("\r\n\r\n".utf8)) == nil) {
            //oversized body, or a head that never ends
            connection.cancel()
        } else if isComplete {
            connection.cancel()
        } else {
            receive(on: connection, buffer: buffer)
        }
    }

    //handle request
    private func handle(_ request: HTTPRequest, on connection: NWConnection, leftover: Data = Data()) {
        //origin check (dns rebinding / browser protection)
        // ->MCP clients aren't browsers; any Origin other than an exact localhost one is refused (incl. 'null')
        if let origin = request.headers["origin"] {
            let allowed = ["http://localhost", "http://127.0.0.1"].contains { origin == $0 || origin.hasPrefix($0 + ":") }
            guard allowed else {
                send(HTTPResponse(status: 403, body: Data("forbidden".utf8), contentType: "text/plain"), on: connection, keepAlive: false)
                return
            }
        }

        guard request.path == "/mcp" || request.path == "/" else {
            send(HTTPResponse(status: 404, body: Data("not found".utf8), contentType: "text/plain"), on: connection, keepAlive: false)
            return
        }

        //auth (bearer token)
        guard MCPServer.tokenMatches(request.headers["authorization"], token: token) else {
            send(HTTPResponse(status: 401, body: Data("unauthorized".utf8), contentType: "text/plain", extraHeaders: ["WWW-Authenticate": "Bearer realm=\"TaskExplorer\""]), on: connection, keepAlive: false)
            return
        }

        log.debug("MCP \(request.method, privacy: .public) \(request.path, privacy: .public) (\(request.body.count) bytes)")

        switch request.method {
        case "POST":
            handleRPC(request.body) { [weak self] response in
                self?.send(response, on: connection, keepAlive: request.keepAlive, leftover: leftover)
            }
        case "GET":
            //no server->client stream
            send(HTTPResponse(status: 405, body: Data(), contentType: "text/plain"), on: connection, keepAlive: request.keepAlive, leftover: leftover)
        case "DELETE":
            send(HTTPResponse(status: 200, body: Data(), contentType: "text/plain"), on: connection, keepAlive: request.keepAlive, leftover: leftover)
        case "OPTIONS":
            send(HTTPResponse(status: 204, body: Data(), contentType: "text/plain"), on: connection, keepAlive: request.keepAlive, leftover: leftover)
        default:
            send(HTTPResponse(status: 405, body: Data(), contentType: "text/plain"), on: connection, keepAlive: false)
        }
    }

    //send response (then read next request, or close)
    private func send(_ response: HTTPResponse, on connection: NWConnection, keepAlive: Bool, leftover: Data = Data()) {
        connection.send(content: response.serialized(keepAlive: keepAlive), completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            //on the server queue (all connection state lives there)
            self.queue.async {
                //activity: a slow request must not be cut off by the idle timer right after it completes
                self.states[ObjectIdentifier(connection)]?.lastActivity = Date()
                if keepAlive { self.receive(on: connection, buffer: leftover) } else { connection.cancel() }
            }
        })
    }

    //constant-time token comparison
    private static func tokenMatches(_ header: String?, token: String) -> Bool {
        guard !token.isEmpty, let header, header.lowercased().hasPrefix("bearer ") else { return false }
        let presented = Array(header.dropFirst(7).trimmingCharacters(in: .whitespaces).utf8)
        let expected = Array(token.utf8)
        guard presented.count == expected.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(presented, expected) { diff |= a ^ b }
        return diff == 0
    }

    /* JSON-RPC */

    //handle (one or a batch of) json-rpc message(s)
    private func handleRPC(_ body: Data, completion: @escaping (HTTPResponse) -> Void) {
        guard let json = try? JSONSerialization.jsonObject(with: body) else {
            completion(HTTPResponse(status: 400, body: rpcError(id: NSNull(), code: -32700, message: "parse error")))
            return
        }
        let messages: [[String: Any]]
        if let batch = json as? [[String: Any]], !batch.isEmpty { messages = batch } else if let one = json as? [String: Any] { messages = [one] } else {
            completion(HTTPResponse(status: 400, body: rpcError(id: NSNull(), code: -32600, message: "invalid request")))
            return
        }
        guard messages.count <= 50 else {
            completion(HTTPResponse(status: 400, body: rpcError(id: NSNull(), code: -32600, message: "batch too large")))
            return
        }

        //test hook: ask the in-app assistant (async: waits for the answer, then returns the new transcript rows)
        // ->not listed in tools/list; only for driving the assistant (Apple Intelligence / Claude / ChatGPT) from a test script
        if messages.count == 1, let message = messages.first, message["method"] as? String == "tools/call",
           let params = message["params"] as? [String: Any], params["name"] as? String == "assistant_ask" {
            let id = message["id"] ?? NSNull()
            let arguments = (params["arguments"] as? [String: Any]) ?? [:]
            _Concurrency.Task { @MainActor in
                let result = await self.askAssistant(arguments)
                let response: [String: Any] = ["jsonrpc": "2.0", "id": id, "result": result]
                completion(HTTPResponse(status: 200, body: (try? JSONSerialization.data(withJSONObject: response)) ?? Data()))
            }
            return
        }

        //dispatch on main (model access)
        DispatchQueue.main.async {
            var responses: [[String: Any]] = []
            for message in messages {
                if let response = self.dispatch(message) { responses.append(response) }
            }
            //notifications only? 202, no body
            if responses.isEmpty {
                completion(HTTPResponse(status: 202, body: Data(), contentType: "application/json"))
                return
            }
            let payload: Any = (json is [Any]) ? responses : responses[0]
            guard JSONSerialization.isValidJSONObject(payload), let data = try? JSONSerialization.data(withJSONObject: payload) else {
                completion(HTTPResponse(status: 500, body: self.rpcError(id: NSNull(), code: -32603, message: "internal error")))
                return
            }
            completion(HTTPResponse(status: 200, body: data))
        }
    }

    //dispatch a single message
    // ->nil for notifications (no response)
    @MainActor private func dispatch(_ message: [String: Any]) -> [String: Any]? {
        let id = message["id"] ?? NSNull()
        guard let method = message["method"] as? String else {
            return ["jsonrpc": "2.0", "id": id, "error": ["code": -32600, "message": "invalid request"]]
        }
        let params = (message["params"] as? [String: Any]) ?? [:]

        //notifications (no id, or explicit notification)
        if method.hasPrefix("notifications/") || message["id"] == nil { return nil }

        let result: Any
        switch method {
        case "initialize":
            result = ["protocolVersion": "2025-06-18",
                      "capabilities": ["tools": ["listChanged": false]],
                      "serverInfo": ["name": "TaskExplorer", "version": getAppVersion() ?? ""],
                      "instructions": "TaskExplorer exposes live macOS process, dylib, open file, and network connection data (from an Endpoint Security system extension) plus VirusTotal results. Use list_keywords to see available #keyword filters such as #3rdparty, #adhoc, #network, #listening, or #flagged."]
        case "ping":
            result = [:] as [String: Any]
        case "tools/list":
            result = ["tools": AssistantTools.all.map { $0.dictionary }]
        case "tools/call":
            guard let name = params["name"] as? String else {
                return ["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "missing tool name"]]
            }
            let arguments = (params["arguments"] as? [String: Any]) ?? [:]
            guard AssistantTools.all.contains(where: { $0.name == name }) else {
                return ["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "unknown tool: \(name)"]]
            }
            do {
                let value = try AssistantTools.call(name, arguments: arguments)
                result = ["content": [["type": "text", "text": AssistantTools.text(value)]], "isError": false]
            } catch {
                result = ["content": [["type": "text", "text": error.localizedDescription]], "isError": true]
            }
        default:
            return ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "method not found: \(method)"]]
        }
        return ["jsonrpc": "2.0", "id": id, "result": result]
    }

    //(test hook) send a prompt to the assistant & wait for it to finish
    // ->arguments: prompt (required), provider ("apple" | "claude" | "chatgpt"; optional), timeout (seconds; default 180)
    @MainActor private func askAssistant(_ arguments: [String: Any]) async -> [String: Any] {
        let assistant = Assistant.shared
        switch (arguments["provider"] as? String)?.lowercased() {
        case "apple": assistant.provider = .apple
        case "claude": assistant.provider = .claude
        case "chatgpt": assistant.provider = .chatGPT
        default: break
        }
        guard let prompt = arguments["prompt"] as? String, !prompt.isEmpty else {
            return ["content": [["type": "text", "text": "missing prompt"]], "isError": true]
        }
        let before = assistant.messages.count
        assistant.send(prompt)
        let deadline = Date().addingTimeInterval(TimeInterval((arguments["timeout"] as? Int) ?? 180))
        while assistant.isBusy, Date() < deadline { try? await _Concurrency.Task.sleep(nanoseconds: 250_000_000) }
        let rows = assistant.messages.dropFirst(before).map { "[\($0.role)] \($0.text)" }
        let failed = assistant.isBusy || assistant.messages.last?.role == .error
        return ["content": [["type": "text", "text": (["provider: \(assistant.provider.label)"] + rows).joined(separator: "\n")]], "isError": failed]
    }

    //json-rpc error (data)
    private func rpcError(id: Any, code: Int, message: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])) ?? Data()
    }
}

//(minimal) http request
struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
    var keepAlive: Bool { headers["connection"]?.lowercased() != "close" }

    //parse: (request, malformed, consumed)
    // ->request nil & !malformed == incomplete (need more bytes); 'consumed' = bytes of this request (head + body)
    static func parse(_ data: Data) -> (request: HTTPRequest?, malformed: Bool, consumed: Int) {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return (nil, false, 0) }
        //bounded head
        guard headerEnd.lowerBound - data.startIndex <= 16 * 1024 else { return (nil, true, 0) }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return (nil, true, 0) }
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return (nil, true, 0) }
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return (nil, true, 0) }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        //no chunked bodies
        guard headers["transfer-encoding"] == nil else { return (nil, true, 0) }
        //bounded, non-negative content length
        guard let length = Int(headers["content-length"] ?? "0"), length >= 0, length <= (1 << 20) else { return (nil, true, 0) }
        let bodyStart = headerEnd.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return (nil, false, 0) }
        let body = data[bodyStart..<(bodyStart + length)]
        var path = String(requestLine[1])
        if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
        return (HTTPRequest(method: String(requestLine[0]).uppercased(), path: path, headers: headers, body: Data(body)), false, (bodyStart + length) - data.startIndex)
    }
}

//(minimal) http response
struct HTTPResponse {
    let status: Int
    let body: Data
    var contentType: String = "application/json"
    var extraHeaders: [String: String] = [:]

    func serialized(keepAlive: Bool) -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 202: reason = "Accepted"
        case 204: reason = "No Content"
        case 400: reason = "Bad Request"
        case 403: reason = "Forbidden"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        default: reason = "Error"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        //note: no CORS headers; browsers have no business talking to this server
        for (key, value) in extraHeaders { head += "\(key): \(value)\r\n" }
        head += "Connection: \(keepAlive ? "keep-alive" : "close")\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }
}

//mcp server port (pref, w/ default)
func mcpServerPort() -> Int {
    let value = UserDefaults.standard.integer(forKey: PREF_MCP_PORT)
    return (1...65535).contains(value) ? value : Int(MCP_DEFAULT_PORT)
}

#endif
