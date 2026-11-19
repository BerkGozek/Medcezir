import Foundation
import Testing
@testable import MedcezirCore

/// Real HTTPS round trip against a private GitHub sandbox repository.
///
/// Skipped unless `MEDCEZIR_LIVE_TESTS=1`. Needs:
/// - `MEDCEZIR_TEST_REPO`: HTTPS URL of a throwaway private repo (never a real project)
/// - `MEDCEZIR_TEST_TOKEN`: a token with push access to it, read from the environment only
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MEDCEZIR_LIVE_TESTS"] == "1"))
struct LiveGitHubTests {
    let env = ProcessInfo.processInfo.environment

    var repoURL: String { env["MEDCEZIR_TEST_REPO"] ?? "" }
    var token: String { env["MEDCEZIR_TEST_TOKEN"] ?? "" }

    func credentials(_ token: String) -> CredentialProvider {
        { _, _ in GitCredential(username: "x-access-token", password: token) }
    }

    @Test func privateCloneCommitPushAndPullOverHTTPS() async throws {
        try #require(!repoURL.isEmpty && !token.isEmpty, "Set MEDCEZIR_TEST_REPO and MEDCEZIR_TEST_TOKEN")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Live-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let me = GitSignature(name: "Medcezir Live Test", email: "medcezir-tests@example.com")

        // Without credentials a private repo must fail with an auth error, not hang or crash.
        do {
            _ = try await GitRepository.clone(from: repoURL, to: root.appendingPathComponent("anon"))
            Issue.record("anonymous clone of a private repo should fail")
        } catch let error as GitError {
            guard case .authenticationFailed = error else { Issue.record("expected auth error, got \(error)"); return }
        }

        // A wrong token is reported as an authentication failure, and the token isn't in the message.
        do {
            _ = try await GitRepository.clone(from: repoURL, to: root.appendingPathComponent("bad"), credentials: credentials("ghp_wrongwrongwrongwrongwrongwrong1234"))
            Issue.record("clone with a wrong token should fail")
        } catch let error as GitError {
            guard case .authenticationFailed = error else { Issue.record("expected auth error, got \(error)"); return }
            #expect(!(error.localizedDescription.contains("ghp_wrong")))
        }

        let a = try await GitRepository.clone(from: repoURL, to: root.appendingPathComponent("a"), credentials: credentials(token))
        let b = try await GitRepository.clone(from: repoURL, to: root.appendingPathComponent("b"), credentials: credentials(token))

        // The token is never written into .git/config.
        let config = try String(contentsOf: a.workingDirectory.appendingPathComponent(".git/config"), encoding: .utf8)
        #expect(!config.contains(token))

        let stamp = ISO8601DateFormatter().string(from: .now)
        try "live test \(stamp)\n".write(to: a.workingDirectory.appendingPathComponent("live-test.txt"), atomically: true, encoding: .utf8)
        try await a.stageAll()
        try await a.commit(message: "Live test \(stamp)", author: me)
        try await a.push(credentials: credentials(token))
        #expect(try await a.outgoingCommits().isEmpty)

        let result = try await b.pull(credentials: credentials(token), author: me)
        #expect(result != .upToDate)
        #expect(try await b.log(limit: 1).first?.summary == "Live test \(stamp)")
    }
}

/// Read-only: lists the token owner's repositories through the real GitHub API.
/// Skipped unless `MEDCEZIR_LIVE_TESTS=1` and `MEDCEZIR_TEST_TOKEN` are set.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MEDCEZIR_LIVE_TESTS"] == "1"))
struct LiveRepositoryListTests {
    @Test func listsRepositoriesIncludingPrivateOnes() async throws {
        let token = ProcessInfo.processInfo.environment["MEDCEZIR_TEST_TOKEN"] ?? ""
        try #require(!token.isEmpty, "Set MEDCEZIR_TEST_TOKEN")
        let account = Account(provider: .github, host: "github.com", username: "x-access-token", displayName: "live")
        let repos = try await RemoteRepositoryLister.repositories(for: account, token: token)
        #expect(!repos.isEmpty)
        #expect(repos.allSatisfy { $0.cloneURL.hasPrefix("https://github.com/") && $0.cloneURL.hasSuffix(".git") })
        #expect(Set(repos.map(\.fullName)).count == repos.count, "pagination must not repeat repositories")
        print("LIVE: \(repos.count) repositories, \(repos.filter(\.isPrivate).count) private; newest: \(repos.prefix(3).map(\.fullName))")
    }
}
