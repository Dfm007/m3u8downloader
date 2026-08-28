(function() {
    const detectedURLs = new Set();
    
    function reportM3U8(url) {
        if (!url || !url.includes('.m3u8')) return;
        const fullURL = new URL(url, window.location.href).href;
        if (!detectedURLs.has(fullURL)) {
            detectedURLs.add(fullURL);
            browser.runtime.sendMessage({ type: 'M3U8_DETECTED', url: fullURL }).catch(() => {});
        }
    }
    
    // Hook XMLHttpRequest
    const origOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
        reportM3U8(url);
        return origOpen.apply(this, arguments);
    };
    
    // Hook fetch
    const origFetch = window.fetch;
    window.fetch = function(input, init) {
        const url = typeof input === 'string' ? input : (input && input.url);
        reportM3U8(url);
        return origFetch.apply(this, arguments);
    };
    
    // Scan DOM
    function scanDOM() {
        document.querySelectorAll('video, source').forEach(el => {
            const src = el.src || el.getAttribute('src');
            reportM3U8(src);
        });
    }
    
    // Scan page source
    function scanSource() {
        const html = document.documentElement.outerHTML;
        const regex = /https?:\/\/[^\s"'<>]+\.m3u8[^\s"'<>]*/g;
        let match;
        while ((match = regex.exec(html)) !== null) {
            reportM3U8(match[0]);
        }
    }
    
    scanDOM();
    scanSource();
    
    const observer = new MutationObserver(() => {
        scanDOM();
    });
    observer.observe(document.body, { childList: true, subtree: true });
})();
