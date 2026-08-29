import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var downloadManager = DownloadManager()
    @State private var detectedResources: [DetectedResource] = []
    @State private var selectedResources: Set<UUID> = []
    @State private var downloadTab: DownloadTab = .active

    // 自定义下载
    @State private var showCustomDownloadSheet = false
    @State private var customURL = ""
    @State private var customName = ""

    // 删除二次确认
    @State private var showDeleteAlert = false
    @State private var taskToDelete: DownloadTask?

    // 导出分享
    @State private var showShareSheet = false
    @State private var shareURL: URL?

    enum DownloadTab: String, CaseIterable {
        case active = "下载中"
        case completed = "已完成"
    }

    var body: some View {
        TabView {
            NavigationView {
                resourceListView
                    .navigationTitle("检测到的资源")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                customURL = ""
                                customName = ""
                                showCustomDownloadSheet = true
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                        }
                    }
            }
            .tabItem {
                Label("资源", systemImage: "list.bullet")
            }

            NavigationView {
                downloadListView
                    .navigationTitle("下载")
            }
            .tabItem {
                Label("下载", systemImage: "arrow.down.circle")
            }
        }
        .onAppear {
            loadDetectedResources()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newResourcesDetected)) { _ in
            loadDetectedResources()
        }
        .sheet(isPresented: $showCustomDownloadSheet) {
            customDownloadSheet
        }
        .alert("确定要删除吗？", isPresented: $showDeleteAlert) {
            Button("删除", role: .destructive) {
                if let task = taskToDelete {
                    downloadManager.delete(task.id)
                    taskToDelete = nil
                }
            }
            Button("取消", role: .cancel) {
                taskToDelete = nil
            }
        } message: {
            Text(taskToDelete?.resourceName ?? "")
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    // MARK: - 自定义下载弹窗

    private var customDownloadSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("m3u8 链接")) {
                    TextField("https://example.com/video.m3u8", text: $customURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section(header: Text("资源名称（可选）")) {
                    TextField("默认取链接文件名", text: $customName)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section {
                    Button(action: startCustomDownload) {
                        Text("开始下载")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .padding(.vertical, 6)
                            .background(customURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                            .cornerRadius(8)
                    }
                    .disabled(customURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("自定义下载")
            .navigationBarItems(
                leading: Button("取消") {
                    showCustomDownloadSheet = false
                }
            )
        }
    }

    private func startCustomDownload() {
        let trimmedURL = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }

        var name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            if let url = URL(string: trimmedURL) {
                let last = url.lastPathComponent
                name = last.replacingOccurrences(of: ".m3u8", with: "", options: [.caseInsensitive])
            }
            if name.isEmpty {
                name = "自定义下载"
            }
        }

        downloadManager.addDownload(resourceName: name, m3u8URL: trimmedURL)
        showCustomDownloadSheet = false
    }

    // MARK: - 资源列表

    private var resourceListView: some View {
        VStack {
            if detectedResources.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "safari")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("暂无检测到的资源")
                        .foregroundColor(.secondary)
                    Text("在 Safari 中打开视频页面，点击扩展图标")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("或点右上角 + 手动输入 m3u8 链接")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(detectedResources) { resource in
                        HStack {
                            Image(systemName: selectedResources.contains(resource.id)
                                  ? "checkmark.circle.fill"
                                  : "circle")
                                .foregroundColor(selectedResources.contains(resource.id) ? .blue : .gray)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(resource.name)
                                    .font(.headline)
                                Text(resource.url)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleSelection(resource.id)
                        }
                    }
                }

                Button(action: startSelectedDownloads) {
                    Text("下载选中 (\(selectedResources.count))")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedResources.isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(selectedResources.isEmpty)
                .padding()
            }
        }
    }

    // MARK: - 下载列表（分页）

    private var downloadListView: some View {
        VStack(spacing: 0) {
            Picker("下载状态", selection: $downloadTab) {
                ForEach(DownloadTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Group {
                switch downloadTab {
                case .active:
                    activeDownloadsList
                case .completed:
                    completedDownloadsList
                }
            }
        }
    }

    private var activeDownloadsList: some View {
        let activeTasks = downloadManager.tasks.filter { $0.status != .completed }

        return Group {
            if activeTasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("暂无下载任务")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(activeTasks) { task in
                        DownloadRow(
                            task: task,
                            onPause: { downloadManager.pause(task.id) },
                            onResume: { downloadManager.resume(task.id) },
                            onCancel: { downloadManager.cancel(task.id) },
                            onRetry: { downloadManager.retry(task.id) },
                            onDelete: {
                                taskToDelete = task
                                showDeleteAlert = true
                            }
                        )
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private var completedDownloadsList: some View {
        let completedTasks = downloadManager.tasks.filter { $0.status == .completed }

        return Group {
            if completedTasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("暂无已完成的下载")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(completedTasks) { task in
                        CompletedDownloadRow(
                            task: task,
                            onExport: {
                                if let fileName = task.outputFileName {
                                    let fileManager = FileManager.default
                                    let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                    let fileURL = documentsURL.appendingPathComponent("Downloads").appendingPathComponent(fileName)
                                    if fileManager.fileExists(atPath: fileURL.path) {
                                        shareURL = fileURL
                                        showShareSheet = true
                                    }
                                }
                            },
                            onDelete: {
                                taskToDelete = task
                                showDeleteAlert = true
                            }
                        )
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - 操作方法

    private func toggleSelection(_ id: UUID) {
        if selectedResources.contains(id) {
            selectedResources.remove(id)
        } else {
            selectedResources.insert(id)
        }
    }

    private func startSelectedDownloads() {
        for resource in detectedResources where selectedResources.contains(resource.id) {
            downloadManager.addDownload(resourceName: resource.name, m3u8URL: resource.url)
        }
        selectedResources.removeAll()
    }

    private func loadDetectedResources() {
        detectedResources = SharedStorage.loadDetectedResources()
    }
}

// MARK: - 分享面板

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 下载中行

struct DownloadRow: View {
    let task: DownloadTask
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.resourceName)
                .font(.headline)

            if task.status == .downloading {
                ProgressView(value: task.progress)
            }

            Text(task.statusText)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                if task.status == .downloading {
                    Button("暂停", action: onPause)
                } else if task.status == .paused {
                    Button("继续", action: onResume)
                }
                if task.status == .failed {
                    Button("重试", action: onRetry)
                }
                if task.status == .cancelled {
                    Button("重试", action: onRetry)
                }
                Button("删除", role: .destructive, action: onDelete)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 已完成行

struct CompletedDownloadRow: View {
    let task: DownloadTask
    let onExport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.resourceName)
                    .font(.headline)
                Text(task.outputFileName ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("导出", action: onExport)
                .font(.caption)
            Button("删除", role: .destructive, action: onDelete)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}