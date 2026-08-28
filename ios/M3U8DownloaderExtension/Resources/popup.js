function getActiveTab() {
    return browser.tabs.query({ active: true, currentWindow: true }).then(tabs => tabs[0]);
}

function renderURLs(urls) {
    const container = document.getElementById('urls');
    if (!urls || urls.length === 0) {
        container.innerHTML = '<div class="empty">No m3u8 URLs detected</div>';
        return;
    }
    container.innerHTML = urls.map(url => {
        return '<div class="url-item"><a href="' + url + '" target="_blank">' + url + '</a></div>';
    }).join('');
}

getActiveTab().then(tab => {
    return browser.tabs.sendMessage(tab.id, { type: 'GET_DETECTED' }).then(response => {
        renderURLs(response ? response.urls : []);
    }).catch(() => {
        browser.runtime.sendMessage({ type: 'GET_DETECTED', tabId: tab.id }).then(response => {
            renderURLs(response ? response.urls : []);
        });
    });
});
