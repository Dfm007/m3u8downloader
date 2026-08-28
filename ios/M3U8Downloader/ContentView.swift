import SwiftUI

struct ContentView: View {
    @StateObject private var downloadManager = DownloadManager()
    @State private var detectedResources: [DetectedResource] = []
    @State private var selectedResources: Set<UUID> = []
    
    var body: some View {
        TabView {
            NavigationView {
                resourceListView
                    .navigationTitle("检测到的资源")
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
    }
    
    private var resourceListView: some View {
        VStack {
            if detectedResources.isEmpty {
                VStack {
                    Image(systemName: "safari")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("暂无检测到的资源")
                        .foregroundColor(.secondary)
                    Text("在 Safari 中打开视频页面，点击扩展图标")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(detectedResources) { resource in
                        HStack {
                            Image(systemName: selectedResources.contains(resource.id) ? "checkmark.circle.fill" : "circle")
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
    
    private var downloadListView: some View {
        Group {
            if downloadManager.tasks.isEmpty {
                VStack {
                    Image(systemName: "arrow.down.circle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("暂无下载任务")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(downloadManager.tasks) { task in
                        DownloadRow(
                            task: task,
                            onPause: { downloadManager.pause(task.id) },
                            onResume: { downloadManager.resume(task.id) },
                            onCancel: { downloadManager.cancel(task.id) },
                            onRetry: { downloadManager.retry(task.id) }
                        )
                    }
                }
            }
        }
    }
    
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

struct DownloadRow: View {
    let task: DownloadTask
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    
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
            
            if let outputFileName = task.outputFileName {
                Text("文件: \(outputFileName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 16) {
                switch task.status {
                case .downloading:
                    Button("暂停", action: onPause)
                    Button("取消", action: onCancel)
                case .paused:
                    Button("继续", action: onResume)
                    Button("取消", action: onCancel)
                case .failed:
                    Button("重试", action: onRetry)
                    Button("取消", action: onCancel)
                case .pending:
                    Button("取消", action: onCancel)
                default:
                    EmptyView()
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}
