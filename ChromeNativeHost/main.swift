import Foundation

// Chrome supplies the origin of the extension whose manifest authorizes this host.
guard CommandLine.arguments.dropFirst().first == "chrome-extension://ogcjfclciffndodfgcnpjagflhjdbcpc/" else { exit(1) }
let input = FileHandle.standardInput
let output = FileHandle.standardOutput
while let prefix = try input.read(upToCount: 4), prefix.count == 4 {
    let size = prefix.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
    guard (1...8192).contains(size) else { break }
    var message = Data()
    while message.count < size,
          let chunk = try input.read(upToCount: size - message.count), !chunk.isEmpty {
        message.append(chunk)
    }
    guard message.count == size else { break }
    let response = try JSONEncoder().encode(BrowserBridge.receive(message, from: .chrome))
    var length = UInt32(response.count).littleEndian
    try output.write(contentsOf: Data(bytes: &length, count: 4))
    try output.write(contentsOf: response)
}
