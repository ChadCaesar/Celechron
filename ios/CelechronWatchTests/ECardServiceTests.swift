import Foundation

private final class MockECardTransport: ECardTransport {
    var responses: [Result<ECardHTTPResponse, ECardServiceError>]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [Result<ECardHTTPResponse, ECardServiceError>]) {
        self.responses = responses
    }

    func execute(
        _ request: URLRequest,
        completion: @escaping (Result<ECardHTTPResponse, ECardServiceError>) -> Void
    ) {
        requests.append(request)
        guard !responses.isEmpty else {
            completion(.failure(.invalidResponse))
            return
        }
        completion(responses.removeFirst())
    }
}

@main
private enum ECardServiceTests {
    private static var assertionCount = 0
    private static var failureCount = 0

    static func main() {
        testExplicitAuthenticationResponses()
        testAuthenticationPagesAndRedirects()
        testTransientAndInvalidResponses()
        testPayloadParsing()
        testPayCodeRequestFlow()

        if failureCount == 0 {
            print("✅ ECardService: \(assertionCount) assertions passed")
        } else {
            print("❌ ECardService: \(failureCount) of \(assertionCount) assertions failed")
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func testExplicitAuthenticationResponses() {
        for status in [401, 403, 901] {
            expectError(response(status: status, body: "{}"), .authenticationExpired,
                        "HTTP \(status) expires authentication")
        }
        for body in [
            #"{"code":401,"data":null}"#,
            #"{"status":"403","data":null}"#,
            #"{"code":901,"data":null}"#,
            #"{"kickout":1,"data":null}"#,
            #"{"data":{"kickout":"1"}}"#,
            #"{"success":false,"message":"token 已过期"}"#,
            #"{"success":false,"msg":"请先登录"}"#,
        ] {
            expectError(response(body: body), .authenticationExpired,
                        "explicit JSON authentication failure is recognized")
        }

        // The word “token” alone is not enough. The server must also report a
        // failed operation and use an explicit authentication marker.
        expectSuccess(
            response(body: #"{"success":true,"message":"token refreshed","data":{}}"#),
            "successful token-related message is not expiry"
        )
    }

    private static func testAuthenticationPagesAndRedirects() {
        expectError(
            response(
                status: 302,
                headers: ["Location": "https://identity.zju.edu.cn/cas/login"],
                body: ""
            ),
            .authenticationExpired,
            "CAS redirect expires authentication"
        )
        expectError(
            response(status: 302, headers: ["Location": "https://example.invalid/maintenance"], body: ""),
            .invalidResponse,
            "unrelated redirect is not mislabeled as authentication expiry"
        )
        expectError(
            response(body: "<!doctype html><form action=\"/cas/login\"><input name=\"username\"><input name=\"password\"></form>"),
            .authenticationExpired,
            "HTTP 200 login HTML expires authentication"
        )
        expectError(
            response(body: "<html><body>maintenance</body></html>"),
            .invalidResponse,
            "non-login HTML is invalid rather than expired"
        )
    }

    private static func testTransientAndInvalidResponses() {
        for status in [408, 425, 429, 500, 503, 599] {
            expectError(response(status: status, body: "{}"), .transientFailure,
                        "HTTP \(status) is retryable")
        }
        expectError(response(status: 404, body: "{}"), .invalidResponse,
                    "HTTP 404 is not authentication expiry")
        expectError(response(body: ""), .invalidResponse, "empty response is invalid")
        expectError(response(body: "not json"), .invalidResponse, "malformed JSON is invalid")
    }

    private static func testPayloadParsing() {
        let cardsJSON: [String: Any] = [
            "data": [
                "card": [
                    ["account": "low", "db_balance": 120],
                    ["account": "high", "db_balance": "9987"],
                    ["account": "", "db_balance": 99999],
                ],
            ],
        ]
        switch ECardPayloadParser.cards(from: cardsJSON) {
        case let .success(cards):
            expect(cards.map(\.account) == ["high", "low"], "highest-balance valid card is selected first")
            expect(cards.first?.balance == 9987, "numeric-string balance is accepted")
        case let .failure(error):
            fail("valid cards rejected: \(error)")
        }

        expect(
            ECardPayloadParser.barcode(from: ["data": ["barcode": ["1234567890"]]])
                == .success("1234567890"),
            "first nonempty barcode is parsed"
        )
        expect(
            ECardPayloadParser.barcode(from: ["data": ["barcode": []]]) == .failure(.noBarcode),
            "empty barcode list has a distinct account-refresh signal"
        )
        expect(
            ECardPayloadParser.barcode(from: ["unexpected": true]) == .failure(.invalidResponse),
            "missing barcode structure is invalid"
        )
    }

    private static func testPayCodeRequestFlow() {
        let refreshTransport = MockECardTransport([
            .success(response(body: #"{"data":{"barcode":[]}}"#)),
            .success(response(body: #"{"data":{"card":[{"account":"fresh","db_balance":5000}]}}"#)),
            .success(response(body: #"{"data":{"barcode":["99887766"]}}"#)),
        ])
        let refreshService = ECardService(transport: refreshTransport)
        var refreshResult: Result<ECardPayCode, ECardServiceError>?
        refreshService.fetchPayCode(auth: "secret", cachedAccount: "stale") { refreshResult = $0 }
        expect(refreshResult == .success(ECardPayCode(
            code: "99887766",
            account: "fresh",
            balance: 5000
        )),
               "empty barcode refreshes account once and retries")
        expect(refreshTransport.requests.count == 3, "account-refresh flow issues exactly three requests")
        expect(refreshTransport.requests[0].url?.query?.contains("account=stale") == true,
               "cached account is attempted first")
        expect(refreshTransport.requests[2].url?.query?.contains("account=fresh") == true,
               "fresh account is used for the retry")

        for error in [ECardServiceError.authenticationExpired, .transientFailure, .invalidResponse] {
            let transport = MockECardTransport([.failure(error)])
            let service = ECardService(transport: transport)
            var result: Result<ECardPayCode, ECardServiceError>?
            service.fetchPayCode(auth: "secret", cachedAccount: "cached") { result = $0 }
            expect(result == .failure(error), "\(error) classification is preserved")
            expect(transport.requests.count == 1, "\(error) does not trigger account refresh")
        }

        let noCacheTransport = MockECardTransport([
            .success(response(body: #"{"data":{"card":[{"account":"only","db_balance":1}]}}"#)),
            .success(response(body: #"{"data":{"barcode":["1234"]}}"#)),
        ])
        let noCacheService = ECardService(transport: noCacheTransport)
        var noCacheResult: Result<ECardPayCode, ECardServiceError>?
        noCacheService.fetchPayCode(auth: "secret", cachedAccount: nil) { noCacheResult = $0 }
        expect(noCacheResult == .success(ECardPayCode(
            code: "1234",
            account: "only",
            balance: 1
        )),
               "missing account fetches ECardWidget card list before barcode")
        expect(noCacheTransport.requests.count == 2, "no-cache flow issues two requests")
    }

    private static func response(
        status: Int = 200,
        headers: [AnyHashable: Any] = ["Content-Type": "application/json"],
        body: String
    ) -> ECardHTTPResponse {
        ECardHTTPResponse(statusCode: status, headers: headers, data: Data(body.utf8))
    }

    private static func expectError(
        _ response: ECardHTTPResponse,
        _ expected: ECardServiceError,
        _ message: String
    ) {
        switch ECardResponseClassifier.jsonObject(from: response) {
        case .success:
            fail(message)
        case let .failure(actual):
            expect(actual == expected, message)
        }
    }

    private static func expectSuccess(_ response: ECardHTTPResponse, _ message: String) {
        switch ECardResponseClassifier.jsonObject(from: response) {
        case .success:
            expect(true, message)
        case .failure:
            fail(message)
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertionCount += 1
        if !condition() {
            failureCount += 1
            print("FAIL: \(message)")
        }
    }

    private static func fail(_ message: String) {
        expect(false, message)
    }
}
