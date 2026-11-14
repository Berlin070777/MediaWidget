(() => {
    if (window !== window.top) return;
    const browserAPI = globalThis.browser ?? chrome;
    const documentID = crypto.randomUUID();
    const mediaEvents = ["play", "playing", "pause", "ended", "loadedmetadata", "emptied", "seeked", "ratechange", "volumechange"];
    let timer;
    let heartbeat;
    let sent = false;
    let inFlight = false;
    let needsPublish = false;

    const text = (value) => typeof value === "string" ? value.trim().slice(0, 300) : "";
    const number = (value) => Number.isFinite(value) ? value : null;
    const meta = (key) => document.querySelector(`meta[property="${key}"]`)?.content;
    const itemID = () => location.pathname.replace(/\/$/, "") + "?p=" +
        (new URLSearchParams(location.search).get("p")?.match(/^\d{1,4}$/)?.[0] ?? "1");

    function player() {
        const root = document.querySelector(".bpx-player-container, #bilibili-player, #bilibiliPlayer");
        if (!root) return null;
        return [...root.querySelectorAll("video")]
            .filter((video) => !video.closest(".bpx-player-ad-wrap") && video.readyState >= 1 &&
                video.currentSrc && video.getBoundingClientRect().width > 0)
            .sort((a, b) => Number(a.paused || a.ended) - Number(b.paused || b.ended) ||
                b.clientWidth * b.clientHeight - a.clientWidth * a.clientHeight)[0] ?? null;
    }

    function read(video) {
        const metadata = navigator.mediaSession?.metadata;
        const pageID = location.pathname.match(/\/video\/(BV[0-9A-Za-z]{10})/)?.[1];
        const canonical = document.querySelector('link[rel="canonical"]')?.href;
        const canonicalID = canonical?.match(/\/video\/(BV[0-9A-Za-z]{10})/)?.[1];
        const pageCover = !pageID || !canonicalID || pageID === canonicalID ? meta("og:image") : null;
        const covers = [pageCover, ...(metadata?.artwork ?? []).map((entry) => entry.src), video.poster];
        let artwork = null;
        for (const cover of covers) {
            if (!cover) continue;
            try {
                const url = new URL(cover, location.href);
                if (/^(https?:)$/.test(url.protocol) && /(^|\.)hdslb\.com$/.test(url.hostname)) {
                    url.protocol = "https:";
                    url.search = "";
                    url.hash = "";
                    artwork = url.href;
                    break;
                }
            } catch {}
        }
        return {
            itemID: itemID(),
            title: text(metadata?.title) || text(document.querySelector("h1.video-title, .video-info-title")?.textContent) ||
                text(meta("og:title")) || text(document.title),
            artist: text(metadata?.artist) || text(document.querySelector(".up-name, .upinfo-name")?.textContent),
            artwork,
            duration: number(video.duration),
            position: number(video.currentTime),
            rate: number(video.playbackRate),
            playing: !video.paused && !video.ended,
            volume: number(video.volume),
            canSeek: Number.isFinite(video.duration) && video.seekable.length > 0
        };
    }

    async function publish() {
        if (inFlight) {
            needsPublish = true;
            return;
        }
        inFlight = true;
        try { await exchange(); } finally {
            inFlight = false;
            if (needsPublish) {
                needsPublish = false;
                schedule();
            }
        }
    }

    async function exchange() {
        const video = player();
        if (!video && !sent) return;
        sent = Boolean(video);
        const response = await browserAPI.runtime.sendMessage({
            type: "mediawidget-state", documentID, state: video ? read(video) : null
        }).catch(() => null);
        const command = response?.command;
        if (!command || command.itemID !== itemID() || !video || video !== player()) return;
        try {
            switch (command.action) {
                case "play": await video.play(); break;
                case "pause": video.pause(); break;
                case "seek":
                    if (Number.isFinite(command.value) && video.seekable.length && Number.isFinite(video.duration)) {
                        video.currentTime = Math.min(video.duration, Math.max(0, command.value));
                    }
                    break;
                case "volume":
                    if (Number.isFinite(command.value)) {
                        video.volume = Math.min(1, Math.max(0, command.value));
                        video.muted = false;
                    }
                    break;
            }
        } catch {}
        schedule();
    }

    function schedule() {
        clearTimeout(timer);
        timer = setTimeout(publish, 100);
    }

    function start() {
        clearInterval(heartbeat);
        heartbeat = setInterval(publish, 2500);
        schedule();
    }

    for (const event of mediaEvents) {
        document.addEventListener(event, (event) => {
            if (event.target instanceof HTMLVideoElement) schedule();
        }, true);
    }
    browserAPI.runtime.onMessage.addListener((message) => {
        if (message?.type === "mediawidget-refresh" && message.documentID === documentID) void publish();
    });
    document.addEventListener("visibilitychange", () => { if (!document.hidden) schedule(); });
    addEventListener("pageshow", start);
    addEventListener("pagehide", () => {
        clearInterval(heartbeat);
        clearTimeout(timer);
        if (sent) browserAPI.runtime.sendMessage({ type: "mediawidget-state", documentID, state: null }).catch(() => {});
        sent = false;
    });
    start();
})();
