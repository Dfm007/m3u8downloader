function getActiveTab() {
    return browser.tabs.query({ active: true, currentWindow: true }).then(tabs => tabs[0]);
}

function escapeHTML(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}

function renderItems(items) {
    const container = document.getElementById('urls');
    if (!items || items.length === 0) {
        container.innerHTML = '<div class="empty">No m3u8 URLs detected</div>';
        return;
    }
    container.innerHTML = items.map(item => {
        const name = escapeHTML(item.name || 'unknown');
        const url = escapeHTML(item.url || '');
        return '<div class="url-item">' +
            '<div class="url-name">' + name + '</div>' +
            '<div class="url-link">' + url + '</div>' +
            '</div>';
    }).join('');
}

getActiveTab().then(tab => {
    return browser.runtime.sendMessage({ type: 'GET_DETECTED', tabId: tab.id }).then(response => {
        renderItems(response ? response.items : []);
    }).catch(() => {
        renderItems([]);
    });
});
