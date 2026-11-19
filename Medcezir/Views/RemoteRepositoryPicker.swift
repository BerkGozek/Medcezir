import MedcezirCore
import SwiftUI

/// The repositories an account can see on its host, searchable. Picking one hands its clone URL
/// back to the clone sheet, so the user never has to copy a link from the website.
struct RemoteRepositoryPicker: View {
    let account: Account
    let onPick: (RemoteRepository) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var repositories: [RemoteRepository]?
    @State private var errorMessage: String?
    @State private var search = ""

    private var filtered: [RemoteRepository] {
        guard let repositories else { return [] }
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return repositories }
        return repositories.filter {
            $0.fullName.localizedCaseInsensitiveContains(query) || ($0.summary?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Button("Try Again", systemImage: "arrow.clockwise") { Task { await load() } }
                }
            }
            if repositories != nil {
                Section {
                    ForEach(filtered) { repository in
                        Button {
                            onPick(repository)
                            dismiss()
                        } label: {
                            RemoteRepositoryRow(repository: repository, account: account,
                                                isCloned: app.repositories.contains { $0.name == repository.name })
                        }
                        .foregroundStyle(.primary)
                    }
                } footer: {
                    Text("Only repositories this account's token can access are listed. For a fine-grained token, that's the repositories you chose when creating it.")
                }
            }
        }
        .overlay {
            if repositories == nil && errorMessage == nil {
                ProgressView("Loading repositories…")
            } else if let repositories, repositories.isEmpty {
                ContentUnavailableView("No Repositories", systemImage: "tray",
                                       description: Text("This token can't see any repositories on \(account.host)."))
            } else if repositories != nil, filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, prompt: "Search repositories")
        .navigationTitle(account.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if repositories == nil { await load() } }
    }

    private func load() async {
        errorMessage = nil
        do {
            guard let token = try app.accountStore.token(for: account) else {
                errorMessage = "This account's token is missing from the Keychain. Remove the account and add it again."
                return
            }
            repositories = try await RemoteRepositoryLister.repositories(for: account, token: token)
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            errorMessage = Redactor.redact(error.localizedDescription)
        }
    }
}

private struct RemoteRepositoryRow: View {
    let repository: RemoteRepository
    let account: Account
    let isCloned: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                // The owner only adds information when it isn't the account itself.
                Text(repository.owner.caseInsensitiveCompare(account.displayName) == .orderedSame ? repository.name : repository.fullName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if repository.isPrivate {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("Private")
                }
                if repository.isFork {
                    Image(systemName: "tuningfork").font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("Fork")
                }
                Spacer(minLength: 0)
                if isCloned {
                    Text("On this \(deviceModel)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let summary = repository.summary {
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if let updated = repository.updatedAt {
                Text("Updated \(updated, format: .relative(presentation: .named))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
