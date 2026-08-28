function getActiveTab() {
    return browser.tabs.query({ active: true, currentWindow: true }).then(tabs => tabs[0]);
}

getActiveTab().then(tab => {
    return browser.tabs.sendMessage(tab.id, { type: 'GET_DETECTED_ITEMS' }).then(response => {
        const items = response ? response.items : [];
        const json = encodeURIComponent(JSON.stringify(items));
        window.location.href = 'm3u8downloader://import?data=' + json;
    }).catch(() => {
        window.location.href = 'm3u8downloader://import';
    });
});
