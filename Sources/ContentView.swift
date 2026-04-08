import SwiftUI
import PhotosUI
import MediaPipeTasksGenAI // 这次引入真正的 AI 推理引擎！

// MARK: - 下载器 (负责搬运 2.4GB 燃料)
class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress: Double = 0.0
    @Published var isDownloading = false
    @Published var isReady = false
    
    let modelURL = URL(string: "https://huggingface.co/huggingworld/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it-web.task?download=true")!
    let localPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("gemma.task")
    
    override init() { super.init(); isReady = FileManager.default.fileExists(atPath: localPath.path) }
    
    func start() {
        isDownloading = true
        URLSession(configuration: .default, delegate: self, delegateQueue: .main).downloadTask(with: modelURL).resume()
    }
    
    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    }
    
    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        try? FileManager.default.moveItem(at: location, to: localPath)
        DispatchQueue.main.async { self.isReady = true; self.isDownloading = false }
    }
}

// MARK: - Obsidian 核心推理引擎
class ObsidianEngine: ObservableObject {
    private var inference: LlmInference?
    @Published var isEngineIgnited = false
    @Published var isThinking = false
    
    // 点火：将 2.4GB 模型载入手机内存
    func igniteEngine(modelPath: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let options = LlmInference.Options(modelPath: modelPath.path)
                let engine = try LlmInference(options: options)
                DispatchQueue.main.async {
                    self.inference = engine
                    self.isEngineIgnited = true
                    print("Obsidian 核心已点亮！")
                }
            } catch {
                print("引擎点火失败: \(error)")
            }
        }
    }
    
    // 推理：利用本地算力生成回答
    func chat(prompt: String) async -> String {
        guard let engine = inference else { return "系统错误：引擎未连接。" }
        DispatchQueue.main.async { self.isThinking = true }
        
        do {
            // Gemma 模型必须遵守的指令格式
            let formattedPrompt = "<start_of_turn>user\n\(prompt)<end_of_turn>\n<start_of_turn>model\n"
            let response = try engine.generateResponse(inputText: formattedPrompt)
            
            DispatchQueue.main.async { self.isThinking = false }
            return response
        } catch {
            DispatchQueue.main.async { self.isThinking = false }
            return "本地推理中断: \(error.localizedDescription)"
        }
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let image: UIImage?
    let isUser: Bool
}

// MARK: - 主界面
struct ContentView: View {
    @StateObject var downloader = ModelDownloader()
    @StateObject var engine = ObsidianEngine()
    @State var text = ""
    @State var messages: [ChatMessage] = []
    @State var selectedItem: PhotosPickerItem? = nil
    
    var body: some View {
        if !downloader.isReady {
            // 下载界面
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                VStack(spacing: 30) {
                    Text("Obsidian 核心未就绪").font(.title2).bold().foregroundColor(.cyan)
                    if downloader.isDownloading {
                        ProgressView(value: downloader.progress).progressViewStyle(LinearProgressViewStyle(tint: .cyan)).padding(.horizontal, 50)
                        Text("\(Int(downloader.progress * 100))%").foregroundColor(.cyan).font(.system(size: 20, design: .monospaced))
                    } else {
                        Button("开始下载核心引擎 (2.4GB)") { downloader.start() }
                            .padding().frame(maxWidth: .infinity).background(Color.cyan.opacity(0.2))
                            .foregroundColor(.cyan).cornerRadius(10).padding(.horizontal, 40)
                    }
                }
            }
        } else if !engine.isEngineIgnited {
            // 模型已下载，正在载入内存 (这需要几秒钟)
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                VStack {
                    ProgressView().colorScheme(.dark)
                    Text("正在将大模型载入神经引擎...").foregroundColor(.cyan).padding(.top)
                }
            }
            .onAppear {
                engine.igniteEngine(modelPath: downloader.localPath)
            }
        } else {
            // 真正的聊天界面
            NavigationView {
                VStack {
                    ScrollView {
                        ScrollViewReader { proxy in
                            VStack(spacing: 15) {
                                ForEach(messages) { msg in
                                    HStack {
                                        if msg.isUser { Spacer() }
                                        VStack(alignment: msg.isUser ? .trailing : .leading) {
                                            if let img = msg.image {
                                                Image(uiImage: img).resizable().scaledToFill().frame(maxWidth: 200, maxHeight: 200).clipped().cornerRadius(10)
                                            }
                                            if !msg.text.isEmpty {
                                                Text(msg.text).padding().background(msg.isUser ? Color.blue : Color.gray.opacity(0.15)).foregroundColor(msg.isUser ? .white : .primary).cornerRadius(12)
                                            }
                                        }
                                        if !msg.isUser { Spacer() }
                                    }.padding(.horizontal)
                                }
                                if engine.isThinking {
                                    HStack {
                                        Text("Obsidian 正在生成...").font(.caption).foregroundColor(.gray).italic()
                                        Spacer()
                                    }.padding(.horizontal)
                                }
                            }
                            .onChange(of: messages.count) { _ in
                                if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                            }
                        }
                    }
                    
                    HStack(spacing: 15) {
                        // 选图按钮 (保留视觉占位，因为 2.4G 模型本身是纯文本模型)
                        PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                            Image(systemName: "photo.on.rectangle.angled").font(.title2).foregroundColor(.blue)
                        }
                        .onChange(of: selectedItem) { newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self), let uiImage = UIImage(data: data) {
                                    messages.append(ChatMessage(text: "", image: uiImage, isUser: true))
                                    messages.append(ChatMessage(text: "视觉模块接入中... (注：当前挂载的 2.4GB 为纯语言模型 Gemma，视觉模态如需真机推理需挂载 PaliGemma 权重包)", image: nil, isUser: false))
                                    selectedItem = nil
                                }
                            }
                        }
                        
                        TextField("输入消息...", text: $text).padding(10).background(Color.gray.opacity(0.1)).cornerRadius(20)
                        
                        Button(action: {
                            if !text.isEmpty {
                                let userText = text
                                messages.append(ChatMessage(text: userText, image: nil, isUser: true))
                                text = ""
                                
                                // 呼叫真实的端侧大模型！
                                Task {
                                    let response = await engine.chat(prompt: userText)
                                    messages.append(ChatMessage(text: response, image: nil, isUser: false))
                                }
                            }
                        }) {
                            Image(systemName: "arrow.up.circle.fill").font(.title).foregroundColor(!text.isEmpty ? .blue : .gray)
                        }.disabled(text.isEmpty || engine.isThinking)
                    }.padding()
                }
                .navigationTitle("Obsidian AI (端侧)")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}
