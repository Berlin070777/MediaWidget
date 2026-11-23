import Foundation

enum AlbumBackArtworkStatus {
    case searching, noMatch, noScan, unavailable, downloadsOff, artworkHidden

    var message: String {
        switch self {
        case .searching: "正在查找真实背封…"
        case .noMatch: "未匹配到专辑发行记录"
        case .noScan: "已匹配专辑，暂无可用背封扫描"
        case .unavailable: "暂时无法查询背封"
        case .downloadsOff: "已关闭在线封面下载"
        case .artworkHidden: "已隐藏封面"
        }
    }
}

actor AlbumBackArtworkLookup {
    static let shared = AlbumBackArtworkLookup()

    struct Match: Sendable {
        let releaseID: UUID?
        let sourceURL: URL?
        let artwork: Data
    }

    enum Failure: Error { case noScan }

    private let clock = ContinuousClock()
    private var nextRequest: ContinuousClock.Instant?
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 14
            configuration.httpAdditionalHeaders = [
                "User-Agent": "MediaWidget/1.5.10 (https://github.com/Berlin070777/MediaWidget)"
            ]
            self.session = URLSession(configuration: configuration)
        }
    }

    func find(title: String, artist: String?) async throws -> Match? {
        guard let artist, !artist.isEmpty, !title.isEmpty, title.count <= 180, artist.count <= 180 else { return nil }
        let album = AlbumTitle(title)
        let titleQuery = Self.searchClause(for: album.spellings, fields: ["releasegroup", "alias", "release"])
        let artistNames = artist.components(separatedBy: " / ")
        let artistQuery = Self.searchClause(for: [artist] + artistNames, fields: ["artist", "artistname"])
        let candidates = try await searchGroups("\(titleQuery) AND \(artistQuery)")
        let matches = rankedGroups(candidates, album: album, artist: artist, artistNames: artistNames)
        let groups: [Group]
        if matches.isEmpty {
            let broader = try await searchGroups(titleQuery)
            groups = rankedGroups(broader, album: album, artist: artist, artistNames: artistNames)
        } else {
            groups = matches
        }
        guard groups.count == 1, let group = groups.first else { return nil }

        let editions: Releases = try await musicBrainz("release", items: [
            .init(name: "release-group", value: group.id.uuidString.lowercased()),
            .init(name: "status", value: "official"),
            .init(name: "limit", value: "100")
        ])
        let backEditions = editions.releases
            .filter { $0.cover?.back == true }
            .map { ($0, album.editionRank(title: $0.title, comment: $0.disambiguation)) }
            .sorted { ($0.1, $0.0.date ?? "9999", $0.0.id.uuidString) < ($1.1, $1.0.date ?? "9999", $1.0.id.uuidString) }
            .map(\.0)

        var downloadError: Error?
        for edition in backEditions.prefix(4) {
            do {
                let data = try await CoverArtArchive.downloadBack(for: edition.id, session: session)
                guard let artwork = await AlbumArtwork.shared.downloadedBackArtwork(data) else {
                    throw CoverArtArchive.Failure.invalidResponse
                }
                return Match(releaseID: edition.id, sourceURL: nil, artwork: artwork)
            } catch CoverArtArchive.Failure.missing {
                continue
            } catch {
                try Task.checkCancellation()
                downloadError = error
            }
        }
        if let supplement = SupplementalBack.forGroup(group.id) {
            let image = try await CoverArtArchive.downloadImage(supplement.imageURL, session: session)
            guard let artwork = await AlbumArtwork.shared.downloadedBackArtwork(image) else {
                throw CoverArtArchive.Failure.invalidResponse
            }
            return Match(releaseID: nil, sourceURL: supplement.sourceURL, artwork: artwork)
        }
        if let downloadError { throw downloadError }
        throw Failure.noScan
    }

    private func searchGroups(_ query: String) async throws -> [Group] {
        let results: SearchResults = try await musicBrainz("release-group", items: [
            .init(name: "query", value: query), .init(name: "limit", value: "24")
        ])
        return results.groups
    }

    private func rankedGroups(_ groups: [Group], album: AlbumTitle, artist: String, artistNames: [String]) -> [Group] {
        let combined = Self.normalized(artist)
        let individual = artistNames.map(Self.normalized)
        let ranked = groups.compactMap { group -> (group: Group, rank: Int)? in
            guard group.matchesArtist(combined: combined, individual: individual),
                  let rank = album.groupRank(main: group.title, alternatives: group.altTitles) else { return nil }
            return (group, rank)
        }
        guard let best = ranked.map(\.rank).min() else { return [] }
        return ranked.filter { $0.rank == best }.map(\.group)
    }

    private func musicBrainz<Response: Decodable>(_ path: String, items: [URLQueryItem]) async throws -> Response {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "musicbrainz.org"
        parts.path = "/ws/2/" + path
        parts.queryItems = items + [.init(name: "fmt", value: "json")]
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = parts.url else { throw CoverArtArchive.Failure.invalidResponse }

        var (data, response) = try await musicBrainzRequest(url)
        if [429, 503].contains(response.statusCode),
           let delay = Int(response.value(forHTTPHeaderField: "Retry-After") ?? "1"), (0...4).contains(delay) {
            try await clock.sleep(for: .seconds(max(1, delay)))
            (data, response) = try await musicBrainzRequest(url)
        }
        guard response.statusCode == 200, data.count <= 4_000_000 else {
            throw CoverArtArchive.Failure.invalidResponse
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func musicBrainzRequest(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        let start = max(clock.now, nextRequest ?? clock.now)
        nextRequest = start.advanced(by: .milliseconds(1150))
        try await clock.sleep(until: start)
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse, response.url?.host == "musicbrainz.org" else {
            throw CoverArtArchive.Failure.invalidResponse
        }
        return (data, response)
    }

    private static func searchClause(for values: [String], fields: [String]) -> String {
        let spellings = Set(values.flatMap { value in
            let traditional = value.applyingTransform(StringTransform("Simplified-Traditional"), reverse: false) ?? value
            let simplified = value.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? value
            return [value, traditional, simplified].map { value in
                value.replacingOccurrences(of: "[’‘ʼ]", with: "'", options: .regularExpression)
            }
        })
        let clauses = spellings.sorted().flatMap { spelling in
            let escaped = spelling.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return fields.map { "\($0):\"\(escaped)\"" }
        }
        return "(" + clauses.joined(separator: " OR ") + ")"
    }

    private static func spacedScripts(_ value: String) -> String {
        value.replacingOccurrences(of: #"(?<=[\p{Latin}0-9])(?=\p{Han})|(?<=\p{Han})(?=[\p{Latin}0-9])"#,
                                   with: " ", options: .regularExpression)
    }

    private static func normalized(_ value: String) -> String {
        let simplified = value.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? value
        return spacedScripts(simplified)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "[’‘ʼ]", with: "'", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private struct AlbumTitle {
        private enum EditionKind {
            case remastered, deluxe, superDeluxe, anniversary

            init?(_ text: String) {
                if text.contains("super deluxe") || text.contains("超级豪华") { self = .superDeluxe }
                else if text.contains("deluxe") || text.contains("豪华版") { self = .deluxe }
                else if text.contains("anniversary") || text.contains("周年") { self = .anniversary }
                else if text.contains("remaster") || text.contains("重制版") || text.contains("重混母带") { self = .remastered }
                else { return nil }
            }
        }

        let spellings: [String]
        private let original: String
        private let base: String
        private let edition: EditionKind?

        init(_ title: String) {
            let spaced = spacedScripts(title)
            let folded = spaced.folding(options: .widthInsensitive, locale: nil)
            original = normalized(spaced)
            if folded.hasSuffix(")"), let open = folded.lastIndex(of: "("),
               let kind = EditionKind(normalized(String(folded[folded.index(after: open)..<folded.index(before: folded.endIndex)]))),
               let main = String(folded[..<open]).nonBlank {
                base = normalized(main)
                edition = kind
                spellings = [title, spaced, main]
            } else {
                base = original
                edition = nil
                spellings = [title, spaced]
            }
        }

        func groupRank(main: String, alternatives: [String]) -> Int? {
            let canonical = normalized(main)
            if canonical == original { return 0 }
            if canonical == base { return 1 }
            let names = alternatives.map(normalized)
            if names.contains(original) { return 2 }
            if names.contains(base) { return 3 }
            return nil
        }

        func editionRank(title: String, comment: String?) -> Int {
            let name = normalized(title)
            if name == original { return 0 }
            if let edition, name == base,
               EditionKind(normalized(comment ?? "")) == edition { return 1 }
            if name == base { return 2 }
            return 3
        }
    }

    private struct SupplementalBack {
        let sourceURL: URL
        let imageURL: URL

        static func forGroup(_ id: UUID) -> Self? {
            // This publisher caption explicitly identifies the Taiwan CD back.
            guard id.uuidString.lowercased() == "5a6ab2b2-952e-3731-a36d-8762c21c2d23" else { return nil }
            return Self(
                sourceURL: URL(string: "https://m.thepaper.cn/newsDetail_forward_31202312")!,
                imageURL: URL(string: "https://imgpai.thepaper.cn/newpai/image/20250717/49da4ae8-6687-4dfc-8855-c2366104bcce.jpeg")!
            )
        }
    }

    private struct SearchResults: Decodable {
        let groups: [Group]
        enum CodingKeys: String, CodingKey { case groups = "release-groups" }
    }

    private struct Group: Decodable {
        let id: UUID
        let title: String
        let aliases: [Name]?
        let artists: [Credit]
        let releases: [NameTitle]?

        enum CodingKeys: String, CodingKey {
            case id, title, aliases, releases
            case artists = "artist-credit"
        }

        var altTitles: [String] { (aliases ?? []).map(\.name) + (releases ?? []).map(\.title) }

        func matchesArtist(combined: String, individual: [String]) -> Bool {
            let credit = artists.map { $0.name + ($0.joinphrase ?? "") }.joined()
            if normalized(credit) == combined { return true }
            guard individual.count == artists.count else { return false }
            var unmatched = artists.map { item in
                Set(([item.name, item.artist.name] + (item.artist.aliases ?? []).map(\.name)).map(normalized))
            }
            for name in individual {
                guard let matched = unmatched.firstIndex(where: { $0.contains(name) }) else { return false }
                unmatched.remove(at: matched)
            }
            return true
        }
    }

    private struct Name: Decodable { let name: String }
    private struct NameTitle: Decodable { let title: String }

    private struct Credit: Decodable {
        let name: String
        let joinphrase: String?
        let artist: Artist
    }

    private struct Artist: Decodable {
        let name: String
        let aliases: [Name]?
    }

    private struct Releases: Decodable { let releases: [Edition] }

    private struct Edition: Decodable {
        struct Cover: Decodable { let back: Bool? }
        let id: UUID
        let title: String
        let date: String?
        let disambiguation: String?
        let cover: Cover?

        enum CodingKeys: String, CodingKey {
            case id, title, date, disambiguation
            case cover = "cover-art-archive"
        }
    }
}
