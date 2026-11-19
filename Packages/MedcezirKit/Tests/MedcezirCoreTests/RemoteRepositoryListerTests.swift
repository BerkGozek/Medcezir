import Foundation
import Testing
@testable import MedcezirCore

/// Serves canned responses by URL path + query, and records the requests it saw.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply { let status: Int; let headers: [String: String]; let body: Data }
    nonisolated(unsafe) static var replies: [String: Reply] = [:]
    nonisolated(unsafe) static var seen: [URLRequest] = []
    static let lock = NSLock()

    static func key(_ url: URL) -> String { "\(url.host() ?? "")\(url.path())?\(url.query() ?? "")" }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.lock.withLock { () -> Reply? in
            Self.seen.append(request)
            return Self.replies[Self.key(request.url!)]
        } ?? Reply(status: 404, headers: [:], body: Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

// Serialized: the stub's replies are shared static state.
@Suite(.serialized) struct RemoteRepositoryListerTests {
    static let account = Account(provider: .github, host: "github.com", username: "x-access-token", displayName: "berk")
    static let firstPage = "api.github.com/user/repos?per_page=100&sort=updated&affiliation=owner,collaborator,organization_member"

    static func repoJSON(_ name: String, owner: String = "BerkGozek", private isPrivate: Bool = false, fork: Bool = false, description: String? = nil) -> String {
        let desc = description.map { "\"\($0)\"" } ?? "null"
        return """
        {"name":"\(name)","full_name":"\(owner)/\(name)","owner":{"login":"\(owner)"},
         "clone_url":"https://github.com/\(owner)/\(name).git","private":\(isPrivate),"fork":\(fork),
         "description":\(desc),"updated_at":"2026-11-18T10:00:00Z","extra_field":42}
        """
    }

    init() {
        StubURLProtocol.lock.withLock { StubURLProtocol.replies = [:]; StubURLProtocol.seen = [] }
    }

    @Test func parsesRepositories() throws {
        let data = Data("[\(Self.repoJSON("Medcezir", private: true, description: "Git client")),\(Self.repoJSON("fork", owner: "someone", fork: true, description: ""))]".utf8)
        let repos = try RemoteRepositoryLister.parseGitHub(data)
        #expect(repos.count == 2)
        #expect(repos[0].fullName == "BerkGozek/Medcezir")
        #expect(repos[0].cloneURL == "https://github.com/BerkGozek/Medcezir.git")
        #expect(repos[0].isPrivate && !repos[0].isFork)
        #expect(repos[0].summary == "Git client")
        #expect(repos[0].updatedAt != nil)
        #expect(repos[1].isFork && repos[1].owner == "someone")
        #expect(repos[1].summary == nil, "an empty description is treated as none")
    }

    @Test func linkHeaderNextPage() {
        let header = #"<https://api.github.com/user/repos?page=2>; rel="next", <https://api.github.com/user/repos?page=5>; rel="last""#
        #expect(RemoteRepositoryLister.nextPage(fromLinkHeader: header)?.absoluteString == "https://api.github.com/user/repos?page=2")
        #expect(RemoteRepositoryLister.nextPage(fromLinkHeader: #"<https://api.github.com/user/repos?page=1>; rel="prev""#) == nil)
        #expect(RemoteRepositoryLister.nextPage(fromLinkHeader: nil) == nil)
    }

    @Test func followsPaginationAndSendsToken() async throws {
        StubURLProtocol.lock.withLock {
            StubURLProtocol.replies[Self.firstPage] = .init(
                status: 200, headers: ["Link": #"<https://api.github.com/user/repos?page=2>; rel="next""#],
                body: Data("[\(Self.repoJSON("one"))]".utf8))
            StubURLProtocol.replies["api.github.com/user/repos?page=2"] = .init(
                status: 200, headers: [:], body: Data("[\(Self.repoJSON("two"))]".utf8))
        }
        let repos = try await RemoteRepositoryLister.repositories(for: Self.account, token: "ghp_test", session: StubURLProtocol.session())
        #expect(repos.map(\.name) == ["one", "two"])
        let seen = StubURLProtocol.lock.withLock { StubURLProtocol.seen }
        #expect(seen.count == 2)
        #expect(seen.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer ghp_test" })
    }

    @Test func neverFollowsPaginationToAnotherHost() async throws {
        StubURLProtocol.lock.withLock {
            StubURLProtocol.replies[Self.firstPage] = .init(
                status: 200, headers: ["Link": #"<https://evil.example.com/steal?page=2>; rel="next""#],
                body: Data("[\(Self.repoJSON("one"))]".utf8))
        }
        let repos = try await RemoteRepositoryLister.repositories(for: Self.account, token: "ghp_test", session: StubURLProtocol.session())
        #expect(repos.count == 1)
        let hosts = StubURLProtocol.lock.withLock { StubURLProtocol.seen.compactMap { $0.url?.host() } }
        #expect(hosts == ["api.github.com"])
    }

    @Test func rejectedTokenGivesClearErrorWithoutToken() async throws {
        StubURLProtocol.lock.withLock {
            StubURLProtocol.replies[Self.firstPage] = .init(status: 401, headers: [:], body: Data(#"{"message":"Bad credentials"}"#.utf8))
        }
        let error = await #expect(throws: RemoteRepositoryError.self) {
            try await RemoteRepositoryLister.repositories(for: Self.account, token: "ghp_supersecret", session: StubURLProtocol.session())
        }
        #expect(error == .tokenRejected)
        let message = error?.localizedDescription ?? ""
        #expect(message.contains("ghp_supersecret") == false)
    }

    @Test func enterpriseUsesItsOwnAPIHost() async throws {
        let enterprise = Account(provider: .github, host: "git.example.com", username: "x-access-token", displayName: "berk")
        StubURLProtocol.lock.withLock {
            StubURLProtocol.replies["git.example.com/api/v3/user/repos?per_page=100&sort=updated&affiliation=owner,collaborator,organization_member"] =
                .init(status: 200, headers: [:], body: Data("[\(Self.repoJSON("inhouse"))]".utf8))
        }
        let repos = try await RemoteRepositoryLister.repositories(for: enterprise, token: "t", session: StubURLProtocol.session())
        #expect(repos.map(\.name) == ["inhouse"])
    }

    @Test func otherProvidersAreUnsupported() async {
        let gitlab = Account(provider: .gitlab, host: "gitlab.com", username: "oauth2", displayName: "berk")
        #expect(!RemoteRepositoryLister.supports(.gitlab))
        await #expect(throws: RemoteRepositoryError.unsupported(.gitlab)) {
            try await RemoteRepositoryLister.repositories(for: gitlab, token: "t", session: StubURLProtocol.session())
        }
    }
}
