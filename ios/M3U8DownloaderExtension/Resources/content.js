(function() {
    const detectedItems = new Map();
    let observer = null;

    function extractName(url, element) {
        if (element && element.getAttribute('title')) {
            return element.getAttribute('title').trim();
        }
        const pageTitle = document.title.trim();
        if (pageTitle && pageTitle.length > 0 && pageTitle.length < 200) {
            return pageTitle;
        }
        try {
            const urlObj = new URL(url, window.location.href);
            const pathParts = urlObj.pathname.split('/').filter(p => p.length > 0);
            if (pathParts.length > 0) {
                const last = pathParts[pathParts.length - 1];
                return last.replace(/\.m3u8.*$/, '');
            }
        } catch (e) {}
        return 'video_' + Date.now();
    }

    function reportM3U8(url, element) {
        if (!url || typeof url !== 'string') return;
        if (!url.includes('.m3u8')) return;
        try {
            const fullURL = new URL(url, window.location.href).href;
            if (!detectedItems.has(fullURL)) {
                const name = extractName(fullURL, element);
                detectedItems.set(fullURL, name);
            }
        } catch (e) {}
    }

    // XHR hook
    const origOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
        try { reportM3U8(url, null); } catch (e) {}
        return origOpen.apply(this, arguments);
    };

    // fetch hook
    const origFetch = window.fetch;
    window.fetch = function(input, init) {
        try {
            const url = typeof input === 'string' ? input : (input && input.url);
            reportM3U8(url, null);
        } catch (e) {}
        return origFetch.apply(this, arguments);
    };

    function scanDOM() {
        document.querySelectorAll('video, source').forEach(el => {
            const src = el.src || el.getAttribute('src');
            reportM3U8(src, el);
        });
    }

    function scanSource() {
        try {
            const html = document.documentElement ? document.documentElement.outerHTML : '';
            const regex = /https?:\/\/[^\s"'<>]+\.m3u8[^\s"'<>]*/g;
            let match;
            while ((match = regex.exec(html)) !== null) {
                reportM3U8(match[0], null);
            }
        } catch (e) {}
    }

    function startObserver() {
        if (observer || !document.body) return;
        observer = new MutationObserver(() => {
            scanDOM();
        });
        observer.observe(document.body, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['src']
        });
    }

    // 立即注册消息监听（必须在任何可能抛异常的代码之前）
    browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
        if (message.type === 'GET_DETECTED_ITEMS') {
            const items = Array.from(detectedItems.entries()).map(([url, name]) => ({ name, url }));
            sendResponse({ items: items });
        }
        return true;
    });

    // 初始扫描（document_start 时 DOM 可能还没就绪）
    function initScan() {
        scanDOM();
        scanSource();
        startObserver();
    }

    if (document.body) {
        initScan();
    } else {
        document.addEventListener('DOMContentLoaded', initScan);
    }
})();