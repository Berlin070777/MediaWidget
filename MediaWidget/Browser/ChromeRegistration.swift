import AppKit

enum ChromeRegistration {
    static let extensionID = "ogcjfclciffndodfgcnpjagflhjdbcpc"
    static let host = "com.mediawidget.bilibili"

    static var extensionURL: URL? {
        Bundle.main.resourceURL?.appending(path: "ChromeExtension", directoryHint: .isDirectory)
    }

    static func register() throws {
        guard let executable = Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "MediaWidgetChromeHost"),
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Google/Chrome/NativeMessagingHosts")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "name": host, "description": "MediaWidget Bilibili",
            "path": executable.path, "type": "stdio",
            "allowed_origins": ["chrome-extension://\(extensionID)/"]
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appending(path: host + ".json"), options: .atomic)
    }
}
