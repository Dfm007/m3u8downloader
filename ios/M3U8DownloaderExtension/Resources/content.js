(function() {
    const detectedURLs = new Map();
    
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
        if (!detectedURLs.has(fullURL)) {
            const name = extractName(fullURL, element);
            detectedURLs.set(fullURL, name);
            browser.runtime.sendMessage({ type: 'M3U8_DETECTED', url: fullURL, name: name }).catch(() => {});
        }
    }
    
    // Hook XMLHttpRequest
    const origOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
        reportM3U8(url, null);
        return origOpen.apply(this, arguments);
    };
    
    // Hook fetch
    const origFetch = window.fetch;
    window.fetch = function(input, init) {
        const url = typeof input === 'string' ? input : (input && input.url);
        reportM3U8(url, null);
        return origFetch.apply(this, arguments);
    };
    
    // Scan DOM
    function scanDOM() {
        document.querySelectorAll('video, source').forEach(el => {
            const src = el.src || el.getAttribute('src');
            reportM3U8(src, el);
        });
    }
    
    // Scan page source
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
})();
