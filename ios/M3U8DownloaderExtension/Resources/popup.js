document.getElementById('openApp').addEventListener('click', function() {
    browser.tabs.query({ active: true, currentWindow: true }).then(tabs => {
        const tab = tabs[0];
        return browser.tabs.sendMessage(tab.id, { type: 'GET_DETECTED_ITEMS' }).then(response => {
            const items = response ? response.items : [];
            const json = encodeURIComponent(JSON.stringify(items));
            window.location.href = 'm3u8downloader://import?data=' + json;
        }).catch(() => {
            window.location.href = 'm3u8downloader://import';
        });
    });
});
