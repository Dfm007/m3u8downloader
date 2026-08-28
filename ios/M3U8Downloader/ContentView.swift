import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var downloadManager = DownloadManager()
    @State private var detectedResources: [DetectedResource] = []
    @State private var selectedResources: Set<UUID> = []
    @State private var downloadTab: DownloadTab = .active
    
    enum DownloadTab: String, CaseIterable {
        case active = "下载中"
        case completed = "已完成"
    }
    
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
                            onDelete: { downloadManager.delete(task.id) }
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
                            onDelete: { downloadManager.delete(task.id) }
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
            
            HStack(spacing: 16) {
                switch task.status {
                case .downloading:
                    Button("暂停", action: onPause)
                    Button("取消", action: onCancel)
                        .foregroundColor(.red)
                case .paused:
                    Button("继续", action: onResume)
                    Button("取消", action: onCancel)
                        .foregroundColor(.red)
                case .failed:
                    Button("重试", action: onRetry)
                case .pending:
                    EmptyView()
                case .cancelled:
                    EmptyView()
                default:
                    EmptyView()
                }
                
                Spacer()
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 已完成行（带导出和删除）

struct CompletedDownloadRow: View {
    let task: DownloadTask
    let onDelete: () -> Void
    @State private var showShareSheet = false
    @State private var showDeleteConfirm = false
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.resourceName)
                    .font(.headline)
                if let fileName = task.outputFileName {
                    Text(fileName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 分享按钮
            Button(action: {
                showShareSheet = true
            }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            
            // 删除按钮（带确认）
            Button(action: {
                showDeleteConfirm = true
            }) {
                Image(systemName: "trash")
                    .font(.title3)
                    .foregroundColor(.red)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showShareSheet) {
            if let fileURL = getFileURL(for: task) {
                ShareSheet(activityItems: [fileURL])
            }
        }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("删除「\(task.resourceName)」？文件也会从磁盘移除。")
        }
    }
    
    private func getFileURL(for task: DownloadTask) -> URL? {
        guard let fileName = task.outputFileName else { return nil }
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent("Downloads").appendingPathComponent(fileName)
    }
}

// MARK: - UIActivityViewController 封装

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}