let detectedURLs = {};

browser.runtime.onMessage.addListener((message, sender) => {
    if (message.type === 'M3U8_DETECTED' && message.url) {
        detectedURLs[sender.tab.id] = detectedURLs[sender.tab.id] || [];
        if (!detectedURLs[sender.tab.id].includes(message.url)) {
            detectedURLs[sender.tab.id].push(message.url);
        }
    }
});

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type === 'GET_DETECTED') {
        sendResponse({ urls: detectedURLs[message.tabId] || [] });
    }
});
