import SwiftUI
import UIKit

// MARK: - 1. 模型下载管理器
class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress: Double = 0.0
    @Published var isDownloading: Bool = false
    @Published var isReady: Bool = false
    @Published var downloadSpeed: String = "0 MB/s"
    
    private var downloadTask: URLSessionDownloadTask?
    private var lastBytesWritten: Int64 = 0
    private var lastTime: Date = Date()
    
    let modelURL = URL(string: "https://huggingface.co/huggingworld/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it-web.task?download=true")!
    let localPath: URL
    
    override init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.localPath = docs.appendingPathComponent("gemma-4-E4B-it-web.task")
        super.init()
        checkIfModelExists()
    }
    
    func checkIfModelExists() {
        if FileManager.default.fileExists(atPath: localPath.path) {
            isReady = true
        }
    }
    
    func startDownload() {
        isDownloading = true
        progress = 0.0
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        downloadTask = session.downloadTask(with: modelURL)
        downloadTask?.resume()
        lastTime = Date()
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let now = Date()
        let timeInterval = now.timeIntervalSince(lastTime)
        if timeInterval > 0.5 {
            let speed = Double(totalBytesWritten - lastBytesWritten) / timeInterval / 1024.0 / 1024.0
            downloadSpeed = String(format: "%.1f MB/s", speed)
            lastTime = now
            lastBytesWritten = totalBytesWritten
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if FileManager.default.fileExists(atPath: localPath.path) {
                try FileManager.default.removeItem(at: localPath)
            }
            try FileManager.default.moveItem(at: location, to: localPath)
            isReady = true
            isDownloading = false
        } catch {
            print("保存模型失败: \(error)")
        }
    }
}

// MARK: - 2. 初始化加载页面 (极客风)
struct BootScreenView: View {
    @ObservedObject var downloader: ModelDownloader
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "cpu")
                .font(.system(size: 80))
                .foregroundColor(.white)
                .shadow(color: .blue, radius: 10, x: 0, y: 0)
            
            Text("Obsidian 核心未加载")
                .font(.title2).bold().foregroundColor(.white)
            
            Text("需要下载本地大模型权重文件 (2.4 GB)\n此过程仅在初次启动时进行。")
                .multilineTextAlignment(.center)
                .font(.footnote)
                .foregroundColor(.gray)
                .padding(.horizontal)
            
            if downloader.isDownloading {
                VStack(spacing: 10) {
                    ProgressView(value: downloader.progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .padding(.horizontal, 40)
                    
                    HStack {
                        Text("\(Int(downloader.progress * 100))%")
                        Spacer()
                        Text(downloader.downloadSpeed)
                    }
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 40)
                }
            } else {
                Button(action: { downloader.startDownload() }) {
                    Text("开始下载核心引擎")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.edgesIgnoringSafeArea(.all))
    }
}

// MARK: - 3. iMessage 数据架构
enum ChatRole { case user, model, system }
struct ChatMessage: Identifiable { let id = UUID(); let role: ChatRole; let content: String; let image: UIImage? }
struct ChatSession: Identifiable { let id = UUID(); var title: String; var messages: [ChatMessage]; var lastModified: Date }

class GemmaInferenceManager: ObservableObject {
    @Published var sessions: [ChatSession] = [ChatSession(title: "新对话", messages: [], lastModified: Date())]
    @Published var isResponding: Bool = false
    
    func createNewSession() { sessions.insert(ChatSession(title: "新对话", messages: [], lastModified: Date()), at: 0) }
    func deleteSession(at offsets: IndexSet) { sessions.remove(atOffsets: offsets); if sessions.isEmpty { createNewSession() } }
    
    func sendMessage(_ text: String, with image: UIImage? = nil, to sessionId: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].messages.append(ChatMessage(role: .user, content: text, image: image))
        if sessions[idx].messages.count <= 2 && !text.isEmpty { sessions[idx].title = String(text.prefix(15)) + (text.count > 15 ? "..." : "") }
        isResponding = true
        
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 1.5)
            let response = image != nil ? "视觉模块已激活，收到图像。(等待推理)" : "这是圆角气泡风格的离线回复。"
            DispatchQueue.main.async {
                self.sessions[idx].messages.append(ChatMessage(role: .model, content: response))
                self.isResponding = false
                let active = self.sessions.remove(at: idx); self.sessions.insert(active, at: 0)
            }
        }
    }
}

// MARK: - 4. 根视图 (路由守卫)
struct ContentView: View {
    @StateObject private var downloader = ModelDownloader()
    @StateObject private var inferenceManager = GemmaInferenceManager()
    
    var body: some View {
        if downloader.isReady {
            ChatListView(manager: inferenceManager)
        } else {
            BootScreenView(downloader: downloader)
        }
    }
}

// MARK: - 5. 聊天列表与详情
struct ChatListView: View {
    @ObservedObject var manager: GemmaInferenceManager
    var body: some View {
        NavigationView {
            List {
                ForEach(manager.sessions) { session in
                    NavigationLink(destination: ChatDetailView(manager: manager, sessionId: session.id)) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.title).font(.headline).lineLimit(1)
                            if let lastMsg = session.messages.last {
                                Text(lastMsg.role == .user ? "你: \(lastMsg.content)" : lastMsg.content).font(.subheadline).foregroundColor(.gray).lineLimit(1)
                            } else { Text("点击开始聊天").font(.subheadline).foregroundColor(.gray) }
                        }.padding(.vertical, 4)
                    }
                }.onDelete(perform: manager.deleteSession)
            }
            .listStyle(PlainListStyle())
            .navigationTitle("信息")
            .navigationBarItems(trailing: Button(action: { manager.createNewSession() }) { Image(systemName: "square.and.pencil").font(.title3) })
        }
    }
}

struct ChatDetailView: View {
    @ObservedObject var manager: GemmaInferenceManager
    let sessionId: UUID
    @State private var inputText: String = ""; @State private var selectedImage: UIImage? = nil; @State private var showingPicker = false
    var currentSession: ChatSession? { manager.sessions.first(where: { $0.id == sessionId }) }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    if let messages = currentSession?.messages { ForEach(messages) { msg in MessageBubble(message: msg) } }
                }.padding()
            }
            VStack(spacing: 0) {
                Divider()
                if let preview = selectedImage {
                    HStack {
                        Image(uiImage: preview).resizable().scaledToFill().frame(width: 60, height: 60).cornerRadius(8).clipped()
                        Button(action: { selectedImage = nil }) { Image(systemName: "xmark.circle.fill").foregroundColor(.gray) }
                        Spacer()
                    }.padding(.horizontal).padding(.top, 8)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    Button(action: { showingPicker = true }) { Image(systemName: "plus").font(.system(size: 20)).foregroundColor(.gray).frame(width: 32, height: 32).background(Color(.systemGray5)).clipShape(Circle()) }.padding(.bottom, 6)
                    TextField("iMessage", text: $inputText).padding(.horizontal, 16).padding(.vertical, 8).background(Color(.systemGray6)).cornerRadius(20).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    if !inputText.isEmpty || selectedImage != nil {
                        Button(action: { manager.sendMessage(inputText, with: selectedImage, to: sessionId); inputText = ""; selectedImage = nil }) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 32)).foregroundColor(.blue) }.padding(.bottom, 6)
                    }
                }.padding(.horizontal).padding(.vertical, 8).background(Color(.systemBackground))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPicker) { ImagePicker(image: $selectedImage) }
    }
}

// MARK: - 6. 纯粹圆角气泡 (彻底告别 Exit Code 65)
struct MessageBubble: View {
    let message: ChatMessage
    var isUser: Bool { message.role == .user }
    var body: some View {
        HStack {
            if isUser { Spacer() }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                if let img = message.image { Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: 220).cornerRadius(16) }
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.body)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(isUser ? Color.blue : Color(.systemGray5))
                        .foregroundColor(isUser ? .white : .primary)
                        .cornerRadius(18) // 这里使用了最基础也是最稳的圆角属性
                }
            }
            if !isUser { Spacer() }
        }
    }
}

// MARK: - 7. 图片选择器
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?; func makeUIViewController(context: Context) -> UIImagePickerController { let p = UIImagePickerController(); p.delegate = context.coordinator; return p }
    func updateUIViewController(_ ui: UIImagePickerController, context: Context) {}; func makeCoordinator() -> Coordinator { Coordinator(self) }
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate { let parent: ImagePicker; init(_ p: ImagePicker) { parent = p }; func imagePickerController(_ p: UIImagePickerController, didFinishPickingMediaWithInfo i: [UIImagePickerController.InfoKey : Any]) { parent.image = i[.originalImage] as? UIImage; p.dismiss(animated: true) } }
}
