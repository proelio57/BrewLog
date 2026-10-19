import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import BrewLog

/// "Ask Claude" request and response handling. No network, so these also run on Linux.
final class BeanAdvisorTests: XCTestCase {
    private let context = BeanAdvisor.Context(
        name: "Gesha Village", roaster: "Fritz", origin: "Ethiopia", process: "Natural", roastLevel: "Light",
        daysOffRoast: 12, gear: ["Comandante C40 (grinder, clicks)", "Hario V60 02 (brewer)"],
        brews: [.init(date: Date(timeIntervalSince1970: 1_760_000_000), recipe: "Ultimate V60", method: "V60",
                      dose: 15, water: 250, temperature: 94, time: 185, grind: "24 clicks", rating: 3,
                      feedback: ["Too sour"], notes: String(repeating: "x", count: 1_000))])

    func testRequest() throws {
        let request = BeanAdvisor.request(context: context, apiKey: "sk-ant-test", language: "German", webSearch: true)
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertNil(body["thinking"], "thinking is always on for this model")
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["type"] as? String, "web_search_20260209")
        let prompt = try XCTUnwrap((body["messages"] as? [[String: Any]])?.first?["content"] as? String)
        XCTAssertTrue(prompt.contains("Coffee: Gesha Village"))
        XCTAssertTrue(prompt.contains(" Ultimate V60 (V60); 15.0 g coffee, 250 g water; 94 °C; 185 s; grind 24 clicks; rated 3/5; taste: Too sour"))
        XCTAssertTrue(prompt.contains("Answer in German."))
        XCTAssertFalse(prompt.contains(String(repeating: "x", count: BeanAdvisor.Limits.maxNotes + 1)), "long notes are cut")

        let offline = BeanAdvisor.request(context: context, apiKey: "k", language: "English", webSearch: false)
        let offlineBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(offline.httpBody)) as? [String: Any])
        XCTAssertNil(offlineBody["tools"])
    }

    func testParsesAnswerWithCitations() throws {
        let json = """
        {"stop_reason": "end_turn", "content": [
          {"type": "server_tool_use", "id": "s1", "name": "web_search", "input": {"query": "Gesha Village"}},
          {"type": "web_search_tool_result", "tool_use_id": "s1", "content": [
            {"type": "web_search_result", "url": "https://example.com/a", "title": "A"},
            {"type": "web_search_result", "url": "https://example.com/b", "title": "B"}]},
          {"type": "text", "text": "Grind a bit finer. ", "citations": [
            {"type": "web_search_result_location", "url": "https://example.com/b", "title": "B", "cited_text": "..."}]},
          {"type": "text", "text": "Use 93 °C.", "citations": [
            {"type": "web_search_result_location", "url": "javascript:alert(1)", "title": "bad"}]}
        ]}
        """
        guard case .answer(let answer) = try BeanAdvisor.parse(Data(json.utf8), status: 200) else { return XCTFail() }
        XCTAssertEqual(answer.text, "Grind a bit finer. Use 93 °C.")
        XCTAssertEqual(answer.sources, [.init(title: "B", url: "https://example.com/b")], "cited pages only, no unsafe links")
    }

    func testParsesPauseRefusalAndErrors() throws {
        let paused = #"{"stop_reason": "pause_turn", "content": [{"type": "server_tool_use", "id": "s1"}]}"#
        guard case .resume = try BeanAdvisor.parse(Data(paused.utf8), status: 200) else { return XCTFail() }
        XCTAssertThrowsError(try BeanAdvisor.parse(Data(#"{"stop_reason": "refusal", "content": []}"#.utf8), status: 200)) {
            XCTAssertEqual($0 as? BeanAdvisor.AdvisorError, .refused)
        }
        XCTAssertThrowsError(try BeanAdvisor.parse(Data(#"{"error": {"message": "bad key"}}"#.utf8), status: 401)) {
            XCTAssertEqual($0 as? BeanAdvisor.AdvisorError, .unauthorized)
        }
        XCTAssertThrowsError(try BeanAdvisor.parse(Data(#"{"error": {"message": "too long"}}"#.utf8), status: 400)) {
            XCTAssertEqual($0 as? BeanAdvisor.AdvisorError, .server(400, "too long"))
        }
        XCTAssertThrowsError(try BeanAdvisor.parse(Data(#"{"stop_reason": "end_turn", "content": []}"#.utf8), status: 200)) {
            XCTAssertEqual($0 as? BeanAdvisor.AdvisorError, .empty)
        }
    }
}
