import CommonCrypto
import Foundation

/// Reads the current track and saved position from the player’s Local Storage journal.
final class NeteasePlaybackState {
    private static let journalPath = "CEFCache/Local Storage/leveldb"
    private static let recordKey = Data([31] + Array("_orpheus://orpheus\0\u{1}lastPlaying".utf8))
    // Fixed encoding key for this local playback record format.
    private static let stateKey = Data(")(13daqP@ssw0rd~".utf8)
    private static let readLimit = 128 * 1_024

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

    func read(in directory: URL) -> Sample? {
        let root = directory.appending(path: Self.journalPath, directoryHint: .isDirectory)
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys)),
              let newest = urls.filter({ $0.pathExtension == "log" && Int($0.deletingPathExtension().lastPathComponent) != nil })
                .max(by: { $0.lastPathComponent < $1.lastPathComponent }),
              let values = try? newest.resourceValues(forKeys: keys), values.isRegularFile == true,
              let size = values.fileSize, size > 0, let modified = values.contentModificationDate else { return nil }

        let current = Journal(url: newest, size: size, modified: modified)
        if current == journal { return sample }
        guard let handle = try? FileHandle(forReadingFrom: newest) else { return nil }
        defer { try? handle.close() }
        let start = max(size - Self.readLimit, 0)
        guard (try? handle.seek(toOffset: UInt64(start))) != nil,
              let bytes = try? handle.read(upToCount: size - start) else { return nil }
        journal = current
        sample = Self.sample(in: bytes)
        return sample
    }

    static func sample(in bytes: Data) -> Sample? {
        var end = bytes.endIndex
        while let record = bytes.range(of: recordKey, options: .backwards, in: bytes.startIndex..<end) {
            end = record.lowerBound
            guard end > bytes.startIndex else { break }
            switch bytes[end - 1] {
            case 0: return nil  // LevelDB deletion of this key.
            case 1:
                let start = record.upperBound
                guard start + 1 < bytes.endIndex else { return nil }
                // The serialized value is a varint length followed by Chromium's
                // one-byte string encoding marker and the player's Base64 payload.
                let encodedLength = Int(bytes[start])
                let extended = encodedLength >= 128
                if extended && bytes[start + 1] >= 128 { return nil }
                let length = extended ? (encodedLength & 127) + Int(bytes[start + 1]) * 128 : encodedLength
                let value = start + (extended ? 2 : 1)
                guard (65...1_025).contains(length), value + length <= bytes.endIndex,
                      bytes[value] == 1,
                      let decoded = Data(base64Encoded: bytes[(value + 1)..<(value + length)]),
                      let playback = decode(decoded) else { return nil }
                return playback
            default: continue
            }
        }
        return nil
    }

    private struct State: Decodable {
        let resourceId: String?
        let trackId: String?
        let current: Double
    }

    private static func decode(_ encrypted: Data) -> Sample? {
        let blockSize = kCCBlockSizeAES128
        guard !encrypted.isEmpty, encrypted.count.isMultiple(of: blockSize) else { return nil }
        let capacity = encrypted.count + blockSize
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
        guard status == kCCSuccess, let state = try? JSONDecoder().decode(State.self, from: clear.prefix(used)),
              state.current.isFinite, (0..<1_000_000).contains(state.current),
              let id = state.resourceId?.nonBlank ?? state.trackId?.nonBlank,
              id.count <= 40 else { return nil }
        return Sample(trackID: id, position: state.current)
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
