let detectedItems = {};

browser.runtime.onMessage.addListener((message, sender) => {
    if (message.type === 'M3U8_DETECTED' && message.url) {
        detectedItems[sender.tab.id] = detectedItems[sender.tab.id] || [];
        const exists = detectedItems[sender.tab.id].some(item => item.url === message.url);
        if (!exists) {
            detectedItems[sender.tab.id].push({ name: message.name || 'unknown', url: message.url });
        }
    }
});

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type === 'GET_DETECTED') {
        sendResponse({ items: detectedItems[message.tabId] || [] });
    }
});
