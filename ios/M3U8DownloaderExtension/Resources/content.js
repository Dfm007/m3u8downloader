(function() {
    const detectedItems = new Map();
    
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
        if (!url || !url.includes('.m3u8')) return;
        const fullURL = new URL(url, window.location.href).href;
        if (!detectedItems.has(fullURL)) {
            const name = extractName(fullURL, element);
            detectedItems.set(fullURL, name);
        }
    }
    
    const origOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
        reportM3U8(url, null);
        return origOpen.apply(this, arguments);
    };
    
    const origFetch = window.fetch;
    window.fetch = function(input, init) {
        const url = typeof input === 'string' ? input : (input && input.url);
        reportM3U8(url, null);
        return origFetch.apply(this, arguments);
    };
    
    function scanDOM() {
        document.querySelectorAll('video, source').forEach(el => {
            const src = el.src || el.getAttribute('src');
            reportM3U8(src, el);
        });
    }
    
    function scanSource() {
        const html = document.documentElement.outerHTML;
        const regex = /https?:\/\/[^\s"'<>]+\.m3u8[^\s"'<>]*/g;
        let match;
        while ((match = regex.exec(html)) !== null) {
            reportM3U8(match[0], null);
        }
    }
    
    scanDOM();
    scanSource();
    
    const observer = new MutationObserver(() => {
        scanDOM();
    });
    observer.observe(document.body, { childList: true, subtree: true });
    
    browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
        if (message.type === 'GET_DETECTED_ITEMS') {
            const items = Array.from(detectedItems.entries()).map(([url, name]) => ({ name, url }));
            sendResponse({ items: items });
        }
    });
})();
