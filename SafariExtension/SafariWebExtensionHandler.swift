import Foundation
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        let profile = item?.userInfo?[SFExtensionProfileKey] as? UUID
        let response = NSExtensionItem()
        if let message, let data = try? JSONSerialization.data(withJSONObject: message),
           let encoded = try? JSONEncoder().encode(BrowserBridge.receive(data, from: .safari, profile: profile)),
           let value = try? JSONSerialization.jsonObject(with: encoded) {
            response.userInfo = [SFExtensionMessageKey: value]
        }
        context.completeRequest(returningItems: [response])
    }
}
