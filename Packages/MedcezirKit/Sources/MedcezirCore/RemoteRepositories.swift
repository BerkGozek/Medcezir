import Foundation

/// A repository on the hosting service that the user can clone.
public struct RemoteRepository: Identifiable, Hashable, Sendable {
    /// "owner/name", unique per host.
    public var id: String { fullName }
    public let fullName: String
    public let name: String
    public let owner: String
    public let cloneURL: String
    public let isPrivate: Bool
    public let isFork: Bool
    public let summary: String?
    public let updatedAt: Date?

    public init(fullName: String, name: String, owner: String, cloneURL: String, isPrivate: Bool, isFork: Bool, summary: String?, updatedAt: Date?) {
        self.fullName = fullName
        self.name = name
        self.owner = owner
        self.cloneURL = cloneURL
        self.isPrivate = isPrivate
        self.isFork = isFork
        self.summary = summary
        self.updatedAt = updatedAt
    }
}

public enum RemoteRepositoryError: Error, LocalizedError, Equatable {
    case unsupported(HostingProvider)
    case tokenRejected
    case forbidden
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let provider): "Listing repositories isn't available for \(provider.displayName) accounts yet."
        case .tokenRejected: "GitHub rejected this account's token. It may have expired; remove the account and add it again with a new token."
        case .forbidden: "GitHub refused the request (HTTP 403). The token may lack access, or the API rate limit was reached. Try again in a few minutes."
        case .http(let status): "GitHub returned HTTP \(status)."
        }
    }
}

/// Lists the repositories an account's token can see, so the user can pick one to clone instead
/// of copying its URL from the website. GitHub only for now (github.com and GitHub Enterprise).
public enum RemoteRepositoryLister {
    /// Stops after this many pages (100 repositories each) so a huge organization can't keep
    /// the sheet loading forever.
    static let maxPages = 10

    public static func supports(_ provider: HostingProvider) -> Bool { provider == .github }

    /// Most recently updated first. With a fine-grained token, GitHub returns only the
    /// repositories that token was given access to.
    public static func repositories(for account: Account, token: String, session: URLSession = .shared) async throws -> [RemoteRepository] {
        guard account.provider == .github else { throw RemoteRepositoryError.unsupported(account.provider) }
        let api = account.host == "github.com" ? "https://api.github.com" : "https://\(account.host)/api/v3"
        var next = URL(string: "\(api)/user/repos?per_page=100&sort=updated&affiliation=owner,collaborator,organization_member")
        var result: [RemoteRepository] = []
        var pages = 0
        while let url = next, pages < maxPages {
            try Task.checkCancellation()
            // Follow pagination only on the API host, so the token is never sent anywhere else.
            guard url.host()?.lowercased() == URL(string: api)?.host()?.lowercased() else { break }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.timeoutInterval = 20
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            switch http?.statusCode ?? 0 {
            case 200..<300: break
            case 401: throw RemoteRepositoryError.tokenRejected
            case 403: throw RemoteRepositoryError.forbidden
            case let status: throw RemoteRepositoryError.http(status)
            }
            result += try parseGitHub(data)
            next = nextPage(fromLinkHeader: http?.value(forHTTPHeaderField: "Link"))
            pages += 1
        }
        return result
    }

    static func parseGitHub(_ data: Data) throws -> [RemoteRepository] {
        struct Item: Decodable {
            struct Owner: Decodable { let login: String }
            let name: String
            let full_name: String
            let owner: Owner
            let clone_url: String
            let `private`: Bool
            let fork: Bool
            let description: String?
            let updated_at: String?
        }
        let iso = ISO8601DateFormatter()
        return try JSONDecoder().decode([Item].self, from: data).map {
            RemoteRepository(
                fullName: $0.full_name, name: $0.name, owner: $0.owner.login, cloneURL: $0.clone_url,
                isPrivate: $0.private, isFork: $0.fork,
                summary: $0.description.flatMap { $0.isEmpty ? nil : $0 },
                updatedAt: $0.updated_at.flatMap { iso.date(from: $0) }
            )
        }
    }

    /// The `rel="next"` URL from a GitHub `Link` header, e.g.
    /// `<https://api.github.com/user/repos?page=2>; rel="next", <…?page=5>; rel="last"`.
    static func nextPage(fromLinkHeader header: String?) -> URL? {
        guard let header else { return nil }
        for part in header.split(separator: ",") {
            let pieces = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count >= 2, pieces.dropFirst().contains("rel=\"next\""),
                  pieces[0].hasPrefix("<"), pieces[0].hasSuffix(">") else { continue }
            return URL(string: String(pieces[0].dropFirst().dropLast()))
        }
        return nil
    }
}
