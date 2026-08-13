//
//  ECardService.swift
//  Celechron
//
//  Shared campus-card HTTP client for the iPhone app bridge, iPhone widget,
//  and independent watchOS requests. Authentication classification lives here
//  so all three entry points make the same decision.
//

import Foundation

enum ECardServiceError: Error, Equatable {
    case authenticationExpired
    case transientFailure
    case invalidResponse
    case noCards
    case noBarcode

    var wireValue: String {
        switch self {
        case .authenticationExpired: return "authenticationExpired"
        case .transientFailure: return "transientFailure"
        case .invalidResponse: return "invalidResponse"
        case .noCards: return "noCards"
        case .noBarcode: return "noBarcode"
        }
    }
}

struct ECardCard: Equatable {
    let account: String
    let balance: Int
}

struct ECardPayCode: Equatable {
    let code: String
    let account: String
    /// Balance in cents. Present when getCampusCards was fetched as part of
    /// this request; nil only for the cached-account fast path.
    let balance: Int?
}

struct ECardHTTPResponse {
    let statusCode: Int
    let headers: [AnyHashable: Any]
    let data: Data

    func header(named name: String) -> String? {
        headers.first { key, _ in
            String(describing: key).caseInsensitiveCompare(name) == .orderedSame
        }.map { String(describing: $0.value) }
    }
}

protocol ECardTransport {
    func execute(
        _ request: URLRequest,
        completion: @escaping (Result<ECardHTTPResponse, ECardServiceError>) -> Void
    )
}

private final class ECardRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Authentication expiry is frequently expressed as a redirect to CAS.
        // Preserve the redirect response for the classifier instead of following it.
        completionHandler(nil)
    }
}

final class URLSessionECardTransport: ECardTransport {
    private let redirectDelegate = ECardRedirectDelegate()
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration, delegate: redirectDelegate, delegateQueue: nil)
    }()

    func execute(
        _ request: URLRequest,
        completion: @escaping (Result<ECardHTTPResponse, ECardServiceError>) -> Void
    ) {
        session.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let response = response as? HTTPURLResponse,
                  let data
            else {
                completion(.failure(.transientFailure))
                return
            }
            completion(.success(ECardHTTPResponse(
                statusCode: response.statusCode,
                headers: response.allHeaderFields,
                data: data
            )))
        }.resume()
    }
}

enum ECardResponseClassifier {
    static func jsonObject(from response: ECardHTTPResponse) -> Result<[String: Any], ECardServiceError> {
        let status = response.statusCode
        let body = String(data: response.data, encoding: .utf8) ?? ""

        if status == 401 || status == 403 || status == 901 {
            return .failure(.authenticationExpired)
        }
        if (300 ..< 400).contains(status) {
            let location = response.header(named: "Location") ?? ""
            if indicatesAuthenticationFailure(location) || indicatesAuthenticationFailure(body) {
                return .failure(.authenticationExpired)
            }
            return .failure(.invalidResponse)
        }
        if status == 408 || status == 425 || status == 429 || (500 ... 599).contains(status) {
            return .failure(.transientFailure)
        }
        guard (200 ... 299).contains(status) else {
            return .failure(.invalidResponse)
        }

        if looksLikeHTML(body) {
            return .failure(
                indicatesAuthenticationFailure(body) ? .authenticationExpired : .invalidResponse
            )
        }
        guard !response.data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: response.data),
              let json = object as? [String: Any]
        else {
            return .failure(.invalidResponse)
        }
        if jsonIndicatesAuthenticationFailure(json) {
            return .failure(.authenticationExpired)
        }
        return .success(json)
    }

    static func jsonIndicatesAuthenticationFailure(_ json: [String: Any]) -> Bool {
        if integer(json["kickout"]) == 1 { return true }
        let code = integer(json["code"]) ?? integer(json["status"])
        if code == 401 || code == 403 || code == 901 { return true }

        let success = boolean(json["success"])
        let message = [json["message"], json["msg"], json["error"]]
            .compactMap(string)
            .joined(separator: " ")
        if success == false, indicatesAuthenticationFailure(message) {
            return true
        }

        for key in ["data", "result"] {
            if let nested = dictionary(json[key]),
               (integer(nested["kickout"]) == 1 || jsonIndicatesAuthenticationFailure(nested))
            {
                return true
            }
        }
        return false
    }

    static func indicatesAuthenticationFailure(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let explicitMarkers = [
            "cas/login",
            "identity.zju.edu.cn",
            "auth/realms/zju",
            "login_ssologin",
            "统一身份认证",
            "请先登录",
            "未登录",
            "登录已失效",
            "登录过期",
            "会话已失效",
            "认证失败",
            "unauthorized",
            "token expired",
            "token已过期",
            "token 已过期",
            "kickout=1",
            "\"kickout\":1",
            "\"kickout\":\"1\"",
        ]
        if explicitMarkers.contains(where: normalized.contains) { return true }
        return normalized.contains("name=\"username\"")
            && normalized.contains("name=\"password\"")
    }

    private static func looksLikeHTML(_ body: String) -> Bool {
        let normalized = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("<!doctype html")
            || normalized.hasPrefix("<html")
            || normalized.contains("<body")
            || normalized.contains("<form")
    }

    fileprivate static func dictionary(_ value: Any?) -> [String: Any]? {
        if let value = value as? [String: Any] { return value }
        if let value = value as? [AnyHashable: Any] {
            return Dictionary(uniqueKeysWithValues: value.map { (String(describing: $0.key), $0.value) })
        }
        return nil
    }

    fileprivate static func array(_ value: Any?) -> [Any]? {
        value as? [Any]
    }

    fileprivate static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    fileprivate static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func boolean(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            if value.caseInsensitiveCompare("true") == .orderedSame || value == "1" { return true }
            if value.caseInsensitiveCompare("false") == .orderedSame || value == "0" { return false }
        }
        return nil
    }
}

enum ECardPayloadParser {
    static func cards(from json: [String: Any]) -> Result<[ECardCard], ECardServiceError> {
        guard let data = ECardResponseClassifier.dictionary(json["data"]),
              let rawCards = ECardResponseClassifier.array(data["card"])
        else {
            return .failure(.invalidResponse)
        }
        let cards = rawCards.compactMap { raw -> ECardCard? in
            guard let card = ECardResponseClassifier.dictionary(raw),
                  let account = ECardResponseClassifier.string(card["account"]),
                  !account.isEmpty
            else {
                return nil
            }
            return ECardCard(
                account: account,
                balance: ECardResponseClassifier.integer(card["db_balance"]) ?? 0
            )
        }
        guard !cards.isEmpty else { return .failure(.noCards) }
        return .success(cards.sorted { $0.balance > $1.balance })
    }

    static func barcode(from json: [String: Any]) -> Result<String, ECardServiceError> {
        guard let data = ECardResponseClassifier.dictionary(json["data"]),
              let values = ECardResponseClassifier.array(data["barcode"])
        else {
            return .failure(.invalidResponse)
        }
        guard let first = values.compactMap(ECardResponseClassifier.string).first,
              !first.isEmpty
        else {
            return .failure(.noBarcode)
        }
        return .success(first)
    }
}

final class ECardService {
    private static let cardsURL = URL(
        string: "https://elife.zju.edu.cn/berserker-app/ykt/tsm/getCampusCards"
    )!
    private static let barcodeBaseURL = URL(
        string: "https://elife.zju.edu.cn/berserker-app/ykt/tsm/batchGetBarCodeGet"
    )!
    private static let userAgent = "E-CampusZJU/2.3.20 (iPhone; iOS 17.5.1; Scale/3.00)"

    private let transport: ECardTransport

    init(transport: ECardTransport = URLSessionECardTransport()) {
        self.transport = transport
    }

    func fetchCards(
        auth: String,
        completion: @escaping (Result<[ECardCard], ECardServiceError>) -> Void
    ) {
        var request = URLRequest(url: Self.cardsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(auth)", forHTTPHeaderField: "Synjones-Auth")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        executeJSON(request) { result in
            completion(result.flatMap(ECardPayloadParser.cards))
        }
    }

    func fetchBarcode(
        auth: String,
        account: String,
        completion: @escaping (Result<String, ECardServiceError>) -> Void
    ) {
        var components = URLComponents(url: Self.barcodeBaseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "account", value: account),
            URLQueryItem(name: "payacc", value: "###"),
            URLQueryItem(name: "paytype", value: "1"),
            URLQueryItem(name: "synAccessSource", value: "app"),
        ]
        guard let url = components.url else {
            completion(.failure(.invalidResponse))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("bearer \(auth)", forHTTPHeaderField: "synjones-auth")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        executeJSON(request) { result in
            completion(result.flatMap(ECardPayloadParser.barcode))
        }
    }

    /// Uses the cached account first. A structurally valid response without a
    /// barcode triggers one account refresh through the same getCampusCards
    /// response used by ECardWidget, followed by one retry. Network and
    /// authentication failures retain their original classification.
    func fetchPayCode(
        auth: String,
        cachedAccount: String?,
        completion: @escaping (Result<ECardPayCode, ECardServiceError>) -> Void
    ) {
        if let cachedAccount, !cachedAccount.isEmpty {
            fetchBarcode(auth: auth, account: cachedAccount) { result in
                switch result {
                case let .success(code):
                    completion(.success(ECardPayCode(
                        code: code,
                        account: cachedAccount,
                        balance: nil
                    )))
                case .failure(.noBarcode):
                    self.fetchUsingFreshAccount(auth: auth, completion: completion)
                case let .failure(error):
                    completion(.failure(error))
                }
            }
        } else {
            fetchUsingFreshAccount(auth: auth, completion: completion)
        }
    }

    private func fetchUsingFreshAccount(
        auth: String,
        completion: @escaping (Result<ECardPayCode, ECardServiceError>) -> Void
    ) {
        fetchCards(auth: auth) { result in
            switch result {
            case let .success(cards):
                guard let card = cards.first else {
                    completion(.failure(.noCards))
                    return
                }
                self.fetchBarcode(auth: auth, account: card.account) { result in
                    completion(result.map {
                        ECardPayCode(code: $0, account: card.account, balance: card.balance)
                    })
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    private func executeJSON(
        _ request: URLRequest,
        completion: @escaping (Result<[String: Any], ECardServiceError>) -> Void
    ) {
        transport.execute(request) { result in
            completion(result.flatMap(ECardResponseClassifier.jsonObject))
        }
    }
}
