import CommonCrypto
import Foundation

/// Reads the player’s local playback state without opening or locking its LevelDB database.
final class NeteasePlaybackState {
    private static let journalPath = "CEFCache/Local Storage/leveldb"
    private static let stateKey = Data(")(13daqP@ssw0rd~".utf8)
    private static let blockSize = 32_768
    private static let readLimit = 512 * 1_024
    private static let playbackKey = storageKey("lastPlaying")
    private static let metadataKey = storageKey("playingInfo")

    private struct Journal: Equatable {
        let url: URL
        let size: Int
        let modified: Date
    }

    struct Sample {
        let trackID: String
        let position: TimeInterval
    }

    private var journal: Journal?
    private var sample: Sample?
    private var metadataValue: Data?
    private var tracks: [NeteaseTrack] = []

    // The two records can be written in different batches when the song changes.
    var currentTrack: NeteaseTrack? {
        guard let sample else { return nil }
        let matched = tracks.filter { $0.identity.id == sample.trackID }
        return matched.first { $0.artworkURL != nil } ?? matched.first
    }

    func read(in directory: URL) -> Sample? {
        let root = directory.appending(path: Self.journalPath, directoryHint: .isDirectory)
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys)) else {
            return nil
        }
        let logs = urls.filter {
            $0.pathExtension == "log" && Int($0.deletingPathExtension().lastPathComponent) != nil
        }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        guard let newest = logs.first,
              let values = try? newest.resourceValues(forKeys: keys), values.isRegularFile == true,
              let size = values.fileSize, let modified = values.contentModificationDate else { return nil }

        let current = Journal(url: newest, size: size, modified: modified)
        if current == journal { return sample }
        guard var records = Self.readRecords(newest, size: size) else { return nil }
        if journal?.url != newest, (records[Self.playbackKey] == nil || records[Self.metadataKey] == nil),
           let older = logs.dropFirst().first,
           let olderValues = try? older.resourceValues(forKeys: keys), olderValues.isRegularFile == true,
           let olderSize = olderValues.fileSize,
           let previous = Self.readRecords(older, size: olderSize) {
            records.merge(previous) { currentValue, _ in currentValue }
        }

        journal = current
        if let value = records[Self.playbackKey] { sample = Self.decodeSample(value) }
        if let value = records[Self.metadataKey], value != metadataValue {
            metadataValue = value
            tracks = Self.decodeTracks(value)
        }
        return sample
    }

    private static func storageKey(_ name: String) -> Data {
        Data(("_orpheus://orpheus\0\u{1}" + name).utf8)
    }

    private static func readRecords(_ file: URL, size: Int) -> [Data: Data]? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let start = max(size - readLimit, 0) / blockSize * blockSize
        guard (try? handle.seek(toOffset: UInt64(start))) != nil else { return nil }
        if size == 0 { return [:] }
        guard let bytes = try? handle.read(upToCount: size - start) else { return nil }
        return records(in: bytes)
    }

    // LevelDB can split a WriteBatch across 32 KiB blocks. Reassemble it
    // before decoding its values, and ignore a batch that is still being written.
    private static func records(in bytes: Data) -> [Data: Data] {
        var records: [Data: Data] = [:]
        var offset = bytes.startIndex
        var fragments: Data?
        while offset + 7 <= bytes.endIndex {
            let blockRemaining = blockSize - offset % blockSize
            if blockRemaining < 7 {
                offset += blockRemaining
                continue
            }
            let length = Int(bytes[offset + 4]) | (Int(bytes[offset + 5]) << 8)
            let type = bytes[offset + 6]
            if type == 0 && length == 0 {
                offset += blockRemaining
                continue
            }
            let end = offset + 7 + length
            guard length <= blockRemaining - 7, end <= bytes.endIndex else { break }
            let payload = bytes[(offset + 7)..<end]
            switch type {
            case 1: // Full record
                fragments = nil
                collect(payload, into: &records)
            case 2: // First fragment
                fragments = Data(payload)
            case 3: // Middle fragment
                fragments?.append(payload)
            case 4: // Last fragment
                if var batch = fragments {
                    fragments = nil
                    batch.append(payload)
                    collect(batch, into: &records)
                }
            default:
                fragments = nil
            }
            offset = end
        }
        return records
    }

    private static func collect(_ batch: Data, into records: inout [Data: Data]) {
        guard batch.count >= 12 else { return }
        let header = batch.startIndex
        let count = Int(batch[header + 8]) | (Int(batch[header + 9]) << 8)
            | (Int(batch[header + 10]) << 16) | (Int(batch[header + 11]) << 24)
        var index = header + 12
        var updates: [Data: Data] = [:]
        for _ in 0..<count {
            guard index < batch.endIndex else { return }
            let tag = batch[index]
            index += 1
            guard tag == 0 || tag == 1, let key = field(in: batch, index: &index) else { return }
            var value = Data()
            if tag == 1 {
                guard let fieldValue = field(in: batch, index: &index) else { return }
                value = fieldValue
            }
            if key == playbackKey || key == metadataKey { updates[key] = value }
        }
        guard index == batch.endIndex else { return }
        // An empty value records a deletion and must supersede older data.
        records.merge(updates) { _, newValue in newValue }
    }

    private static func field(in batch: Data, index: inout Int) -> Data? {
        var length = 0
        for shift in stride(from: 0, to: 35, by: 7) {
            guard index < batch.endIndex else { return nil }
            let byte = Int(batch[index])
            index += 1
            length |= (byte & 127) << shift
            if byte < 128 {
                guard length <= batch.endIndex - index else { return nil }
                let start = index
                index += length
                return batch[start..<index]
            }
        }
        return nil
    }

    private struct State: Decodable {
        let resourceId: String?
        let trackId: String?
        let current: Double
    }

    private static func decodeSample(_ value: Data) -> Sample? {
        guard let clear = decrypt(value), let state = try? JSONDecoder().decode(State.self, from: clear),
              state.current.isFinite, (0..<1_000_000).contains(state.current),
              let id = state.resourceId?.nonBlank ?? state.trackId?.nonBlank, id.count <= 40 else { return nil }
        return Sample(trackID: id, position: state.current)
    }

    private static func decodeTracks(_ value: Data) -> [NeteaseTrack] {
        guard let clear = decrypt(value),
              let object = (try? JSONSerialization.jsonObject(with: clear)) as? [String: Any] else { return [] }
        let playing = object["curPlaying"] as? [String: Any]
        let candidates = [object["curTrack"], playing?["track"]]
        return candidates.compactMap { candidate in
            guard let metadata = candidate as? [String: Any],
                  let id = (metadata["id"] as? String)?.nonBlank ?? (metadata["id"] as? NSNumber)?.stringValue,
                  id.count <= 40 else { return nil }
            return NeteaseTrack(id: id, metadata: metadata)
        }
    }

    private static func decrypt(_ value: Data) -> Data? {
        guard value.first == 1, let encrypted = Data(base64Encoded: value.dropFirst()),
              !encrypted.isEmpty, encrypted.count.isMultiple(of: kCCBlockSizeAES128) else { return nil }
        let capacity = encrypted.count + kCCBlockSizeAES128
        var clear = Data(count: capacity)
        var used = 0
        let status = clear.withUnsafeMutableBytes { output in
            stateKey.withUnsafeBytes { key in
                encrypted.withUnsafeBytes { input in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding), key.baseAddress, key.count, nil,
                            input.baseAddress, input.count, output.baseAddress, capacity, &used)
                }
            }
        }
        return status == kCCSuccess ? Data(clear.prefix(used)) : nil
    }
}

struct NeteaseProgress {
    private var trackID: String?
    private var lastPosition: TimeInterval?
    private var anchor: (position: TimeInterval, date: Date)?
    private var playing = false

    mutating func position(for trackID: String?, duration: TimeInterval?, sample: NeteasePlaybackState.Sample?,
                           isPlaying: Bool, at now: Date) -> TimeInterval? {
        if trackID != self.trackID {
            self = NeteaseProgress()
            self.trackID = trackID
        }
        guard let trackID else { return nil }

        if let sample, sample.trackID == trackID, sample.position != lastPosition,
           duration.map({ sample.position <= $0 + 2 }) ?? true {
            lastPosition = sample.position
            anchor = (sample.position, now)
        } else if playing != isPlaying, let position = projected(at: now) {
            // When NetEase hasn't flushed a new position yet, freeze on pause
            // or start advancing again from the last position on resume.
            anchor = (position, now)
        }
        playing = isPlaying
        return projected(at: now).map { min($0, duration ?? .infinity) }
    }

    private func projected(at now: Date) -> TimeInterval? {
        anchor.map { $0.position + (playing ? max(0, now.timeIntervalSince($0.date)) : 0) }
    }
}
