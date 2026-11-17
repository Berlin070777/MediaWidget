const browserAPI = globalThis.browser ?? chrome;
const nativeHost = "com.mediawidget.bilibili";

const isSafari = typeof ServiceWorkerGlobalScope === "undefined";
let nativePort;
let safariPort;
const safariTabs = new Map();

function connectSafari() {
    if (safariPort) return;
    try {
        safariPort = browserAPI.runtime.connectNative(nativeHost);
        safariPort.onMessage.addListener((message) => {
            const key = (message?.documentID ?? message?.userInfo?.documentID)?.toLowerCase();
            const tabID = safariTabs.get(key);
            if (Number.isInteger(tabID)) {
                browserAPI.tabs.sendMessage(tabID, { type: "mediawidget-refresh", documentID: key }).catch(() => {});
            }
        });
        safariPort.onDisconnect.addListener(() => { safariPort = null; });
    } catch { safariPort = null; }
}
const pending = new Map();

function sendNative(payload) {
    if (isSafari) return browserAPI.runtime.sendNativeMessage(nativeHost, payload);
    if (!nativePort) {
        nativePort = browserAPI.runtime.connectNative(nativeHost);
        nativePort.onMessage.addListener(({ requestID, command }) => {
            const finish = pending.get(requestID?.toLowerCase());
            if (finish) finish({ command });
        });
        nativePort.onDisconnect.addListener(() => {
            void browserAPI.runtime.lastError;
            nativePort = null;
            for (const finish of pending.values()) finish(null);
        });
    }
    return new Promise((resolve) => {
        const requestID = crypto.randomUUID().toLowerCase();
        const timer = setTimeout(() => finish(null), 3000);
        function finish(response) {
            clearTimeout(timer);
            pending.delete(requestID);
            resolve(response);
        }
        pending.set(requestID, finish);
        try { nativePort.postMessage({ ...payload, requestID }); } catch { finish(null); }
    });
}

if (isSafari) {
    browserAPI.tabs.onRemoved.addListener((tabID) => {
        for (const [documentID, mappedTab] of safariTabs) {
            if (mappedTab !== tabID) continue;
            safariTabs.delete(documentID);
            // Safari can tear down the content script before it reports pagehide.
            void sendNative({ documentID, state: null }).catch(() => {});
        }
    });
}

browserAPI.runtime.onMessage.addListener((message, sender, reply) => {
    if (message?.type !== "mediawidget-state" || (sender.frameId != null && sender.frameId !== 0) ||
        !Number.isInteger(sender.tab?.id) || !/^[\da-f-]{36}$/i.test(message.documentID)) return false;
    let url;
    try { url = new URL(sender.url); } catch { return false; }
    if (url.origin !== "https://www.bilibili.com" ||
        !/^\/(video\/[^/]+|bangumi\/play\/[^/]+)/.test(url.pathname)) return false;

    if (isSafari) {
        if (message.state) {
            safariTabs.set(message.documentID.toLowerCase(), sender.tab.id);
            connectSafari();
        } else {
            safariTabs.delete(message.documentID.toLowerCase());
        }
    }

    sendNative({
        documentID: message.documentID,
        state: message.state
    }).then(async (response) => {
        if (response?.command?.action === "activate") {
            await browserAPI.tabs.update(sender.tab.id, { active: true });
            if (Number.isInteger(sender.tab.windowId)) {
                await browserAPI.windows.update(sender.tab.windowId, { focused: true });
            }
            reply(null);
        } else {
            reply(response ?? null);
        }
    }).catch(() => reply(null));
    return true;
});
