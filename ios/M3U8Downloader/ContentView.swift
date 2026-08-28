import SwiftUI

struct ContentView: View {
    @StateObject private var downloader = M3U8Downloader()
    @State private var m3u8URLString = ""
    @State private var filename = "video"
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("m3u8 URL")
                        .font(.headline)
                    TextField("https://example.com/video.m3u8", text: $m3u8URLString)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    Text("Filename")
                        .font(.headline)
                    TextField("video", text: $filename)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding(.horizontal)
                
                if downloader.isDownloading {
                    ProgressView(value: downloader.progress) {
                        Text(downloader.statusText)
                            .font(.caption)
                    }
                    .padding(.horizontal)
                    
                    Button("Cancel") {
                        downloader.cancel()
                    }
                    .foregroundColor(.red)
                } else {
                    Button(action: startDownload) {
                        Text("Download")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)
                    .disabled(m3u8URLString.isEmpty)
                }
                
                if !downloader.downloadedFiles.isEmpty {
                    List {
                        Section("Downloaded") {
                            ForEach(downloader.downloadedFiles, id: \.self) { url in
                                Text(url.lastPathComponent)
                                    .font(.caption)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .navigationTitle("m3u8 Downloader")
        }
    }
    
    private func startDownload() {
        guard let url = URL(string: m3u8URLString) else { return }
        downloader.download(m3u8URL: url, filename: filename)
    }
}

#Preview {
    ContentView()
}
