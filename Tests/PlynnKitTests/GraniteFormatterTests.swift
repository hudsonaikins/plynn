import XCTest
@testable import PlynnKit

final class GraniteFormatterTests: XCTestCase {
    func testUnavailableServerKeepsOriginalText() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UnavailableServer.self]
        let granite = GraniteFormatter(session: URLSession(configuration: configuration))
        let available = await granite.available()
        XCTAssertFalse(available)
        let text = "um ship friday actually monday"
        let result = await granite.format(text, tone: .neutral, technical: false,
                                          preferredSpellings: [])
        XCTAssertEqual(result, text)
    }

    func testLiveLocalPolishOrRulesFallback() async throws {
        guard ProcessInfo.processInfo.environment["PLYNN_VALIDATE_GRANITE"] == "1" else {
            throw XCTSkip("Set PLYNN_VALIDATE_GRANITE=1 to validate the loopback MLX server")
        }
        let granite = GraniteFormatter()
        let available = await granite.available()
        XCTAssertTrue(available, "Granite MLX server must be running on loopback port 8766")
        let raw = "um open context snapshot dot swift"
        let result = await granite.format(raw, tone: .neutral, technical: true,
                                          preferredSpellings: ["ContextSnapshot.swift"])
        XCTAssertNotEqual(result, raw, "Model did not produce a usable cleanup")
        XCTAssertTrue(result.lowercased().contains("context"), result)
        print("GRANITE_POLISH raw=\(raw) output=\(result)")
        let formatter = TranscriptFormatter()
        let engine = await formatter.polishEngine
        XCTAssertEqual(engine, "Granite 3.3 2B (local MLX)")
        let formatted = await formatter.format(raw, bundleID: "com.openai.codex", aiPolish: true)
        XCTAssertTrue(formatted.text.lowercased().contains("context"), formatted.text)
        XCTAssertFalse(formatted.text.lowercased().hasPrefix("um "), formatted.text)
    }
}

private final class UnavailableServer: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 503,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
