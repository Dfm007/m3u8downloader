function getActiveTab() {
    return browser.tabs.query({ active: true, currentWindow: true }).then(tabs => tabs[0]);
}

getActiveTab().then(tab => {
    return browser.tabs.sendMessage(tab.id, { type: 'JUMP_TO_APP' }).then(() => {
        window.close();
    }).catch(() => {
        document.body.innerHTML = '<div style="padding:20px;font-family:-apple-system;">Failed to jump to app</div>';
    });
});
