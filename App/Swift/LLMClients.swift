//
//  LLMClients.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: (raw HTTP) clients for Claude (Anthropic Messages API) & ChatGPT (OpenAI Chat Completions)
//        ...each keeps its own conversation history, and runs the tool-use loop w/ AssistantTools

import Foundation

//max tool-use rounds per user message
private let maxToolRounds = 24

/* CLAUDE */

//note: clients are main-actor isolated, so 'history' is never mutated concurrently (network awaits release the actor)
@MainActor final class ClaudeClient: LLMClient {

    private let apiKey: String
    private let model = "claude-opus-5"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    //conversation history (messages api format)
    private var history: [[String: Any]] = []

    init(apiKey: String) { self.apiKey = apiKey }

    func reset() { history = [] }

    //tools (messages api format)
    private var tools: [[String: Any]] {
        AssistantTools.all.map { ["name": $0.name, "description": $0.description, "input_schema": $0.schema] }
    }

    func run(userMessage: String, systemPrompt: String, onEvent: @escaping (LLMEvent) async -> Void) async throws {
        //note: on any failure the whole exchange (user turn + tool rounds) is rolled back, so history never ends in an
        //      unanswered tool_use (which the API rejects forever after) or in the oversized tool results that caused a 400
        let checkpoint = history.count
        history.append(["role": "user", "content": userMessage])
        var rounds = 0
        while true {
            do { try _Concurrency.Task.checkCancellation() } catch { history.removeSubrange(checkpoint...); throw error }
            let body: [String: Any] = ["model": model,
                                       "max_tokens": 16000,
                                       "system": [["type": "text", "text": systemPrompt, "cache_control": ["type": "ephemeral"]]],
                                       "tools": tools,
                                       "fallbacks": "default",
                                       "messages": history]
            let response: [String: Any]
            do {
                response = try await postJSON(endpoint, headers: ["x-api-key": apiKey, "anthropic-version": "2023-06-01", "anthropic-beta": "server-side-fallback-2026-07-01"], body: body)
            } catch {
                history.removeSubrange(checkpoint...)
                throw error
            }
            let content = (response["content"] as? [[String: Any]]) ?? []
            let stopReason = response["stop_reason"] as? String

            //echo assistant turn (unchanged; includes thinking/tool_use blocks)
            history.append(["role": "assistant", "content": content])

            //text
            let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !text.isEmpty { await onEvent(.text(text)) }

            if stopReason == "refusal" {
                let explanation = ((response["stop_details"] as? [String: Any])?["explanation"] as? String) ?? "the request was declined"
                throw LLMError(message: "Claude declined: \(explanation)")
            }

            //truncated?
            if stopReason == "max_tokens" { await onEvent(.text("(response truncated)")) }

            //tool calls? (any tool_use block must be answered, whatever the stop reason)
            let toolUses = content.filter { $0["type"] as? String == "tool_use" }
            guard !toolUses.isEmpty else { return }
            rounds += 1
            guard rounds <= maxToolRounds else {
                history.removeSubrange(checkpoint...)
                throw LLMError(message: "too many tool calls; try a narrower question")
            }

            var results: [[String: Any]] = []
            for use in toolUses {
                let name = (use["name"] as? String) ?? ""
                let input = (use["input"] as? [String: Any]) ?? [:]
                await onEvent(.toolCall(name: name, arguments: JSON.string(input)))
                let result = await invokeTool(name, arguments: input)
                results.append(["type": "tool_result", "tool_use_id": use["id"] ?? "", "content": result.text, "is_error": result.isError])
            }
            history.append(["role": "user", "content": results])
        }
    }
}

/* CHATGPT (OPENAI) */

@MainActor final class OpenAIClient: LLMClient {

    private let apiKey: String
    private let model = "gpt-5"
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    //conversation history (chat completions format; system message first)
    private var history: [[String: Any]] = []

    init(apiKey: String) { self.apiKey = apiKey }

    func reset() { history = [] }

    //tools (chat completions format)
    private var tools: [[String: Any]] {
        AssistantTools.all.map { ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.schema]] }
    }

    func run(userMessage: String, systemPrompt: String, onEvent: @escaping (LLMEvent) async -> Void) async throws {
        if history.isEmpty { history.append(["role": "system", "content": systemPrompt]) }
        //note: any failure rolls the whole exchange back (see ClaudeClient.run)
        let checkpoint = history.count
        history.append(["role": "user", "content": userMessage])
        var rounds = 0
        while true {
            do { try _Concurrency.Task.checkCancellation() } catch { history.removeSubrange(checkpoint...); throw error }
            let body: [String: Any] = ["model": model, "tools": tools, "messages": history, "max_completion_tokens": 16000]
            let response: [String: Any]
            do {
                response = try await postJSON(endpoint, headers: ["authorization": "Bearer \(apiKey)"], body: body)
            } catch {
                history.removeSubrange(checkpoint...)
                throw error
            }
            guard let choice = (response["choices"] as? [[String: Any]])?.first, let message = choice["message"] as? [String: Any] else {
                throw LLMError(message: "unexpected response from OpenAI")
            }
            history.append(message)
            if choice["finish_reason"] as? String == "length" { await onEvent(.text("(response truncated)")) }

            if let text = message["content"] as? String, !text.isEmpty { await onEvent(.text(text)) }

            let calls = (message["tool_calls"] as? [[String: Any]]) ?? []
            guard !calls.isEmpty else { return }
            rounds += 1
            guard rounds <= maxToolRounds else {
                history.removeSubrange(checkpoint...)
                throw LLMError(message: "too many tool calls; try a narrower question")
            }

            for call in calls {
                let function = (call["function"] as? [String: Any]) ?? [:]
                let name = (function["name"] as? String) ?? ""
                let argsString = (function["arguments"] as? String) ?? "{}"
                let args = (try? JSONSerialization.jsonObject(with: Data(argsString.utf8)) as? [String: Any]) ?? [:]
                await onEvent(.toolCall(name: name, arguments: argsString))
                let result = await invokeTool(name, arguments: args)
                history.append(["role": "tool", "tool_call_id": call["id"] ?? "", "content": result.text])
            }
        }
    }
}
