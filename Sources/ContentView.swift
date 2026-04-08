import SwiftUI
import UIKit

// MARK: - 1. 数据模型 (支持多窗口)
enum ChatRole { case user, model, system }

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let content: String
    let image: UIImage?
}

struct ChatSession: Identifiable {
    let id = UUID()
    var title: String
    var messages: [ChatMessage]
    var lastModified: Date
}

// MARK: - 2. 核心推理与记忆管理器
class GemmaInferenceManager: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var isResponding: Bool = false
    
    init() {
        // 默认创建一个初始会话
        createNewSession(title: "新对话")
    }
    
    func createNewSession(title: String = "新对话") {
        let newSession = ChatSession(title: title, messages: [], lastModified: Date())
        sessions.insert(newSession, at: 0) // 新会话放在最上面
    }
    
    func deleteSession(at offsets: IndexSet) {
        sessions.remove(atOffsets: offsets)
        if sessions.isEmpty {
            createNewSession() // 如果删空了，自动建一个兜底
        }
    }
    
    func sendMessage(_ text: String, with image: UIImage? = nil, to sessionId: UUID) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        
        let userMessage = ChatMessage(role: .user, content: text, image: image)
        sessions[sessionIndex].messages.append(userMessage)
        
        // 自动将第一句话设为标题
        if sessions[sessionIndex].messages.count <= 2 && !text.isEmpty {
            sessions[sessionIndex].title = String(text.prefix(15)) + (text.count > 15 ? "..." : "")
        }
        
        sessions[sessionIndex].lastModified = Date()
        isResponding = true
        
        // 模拟端侧模型处理
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 1.5)
            let responseText = image != nil ? "已收到图像：\"\(text)\"。(等待本地视觉模型权重替换)" : "这是 iMessage 风格的本地回复。"
            
            DispatchQueue.main.async {
                self.sessions[sessionIndex].messages.append(ChatMessage(role: .model, content: responseText))
                self.sessions[sessionIndex].lastModified = Date()
                self.isResponding = false
                
                // 将有新消息的会话顶到最上面
                let activeSession = self.sessions.remove(at: sessionIndex)
                self.sessions.insert(activeSession, at: 0)
            }
        }
    }
}

// MARK: - 3. UI 界面：消息列表 (iMessage 首页)
struct ContentView: View {
    @StateObject private var inferenceManager = GemmaInferenceManager()
    
    var body: some View {
        NavigationView {
            List {
                ForEach(inferenceManager.sessions) { session in
                    NavigationLink(destination: ChatDetailView(manager: inferenceManager, sessionId: session.id)) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.title)
                                .font(.headline)
                                .lineLimit(1)
                            if let lastMsg = session.messages.last {
                                Text(lastMsg.role == .user ? "你: \(lastMsg.content)" : lastMsg.content)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            } else {
                                Text("点击开始聊天")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: inferenceManager.deleteSession)
            }
            .listStyle(PlainListStyle())
            .navigationTitle("信息") // 致敬 iMessage
            .navigationBarItems(trailing: Button(action: {
                inferenceManager.createNewSession()
            }) {
                Image(systemName: "square.and.pencil") // iMessage 的新建图标
                    .font(.title3)
            })
        }
    }
}

// MARK: - 4. UI 界面：聊天详情 (iMessage 聊天框)
struct ChatDetailView: View {
    @ObservedObject var manager: GemmaInferenceManager
    let sessionId: UUID
    
    @State private var inputText: String = ""
    @State private var selectedImage: UIImage? = nil
    @State private var showingPicker = false
    
    var currentSession: ChatSession? {
        manager.sessions.first(where: { $0.id == sessionId })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 聊天气泡滚动区
            ScrollView {
                VStack(spacing: 12) {
                    if let messages = currentSession?.messages {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                        }
                    }
                }
                .padding()
            }
            
            // 底部输入区 (复刻 iOS 16 原生样式)
            VStack(spacing: 0) {
                Divider()
                
                if let preview = selectedImage {
                    HStack {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                            .clipped()
                        Button(action: { selectedImage = nil }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                
                HStack(alignment: .bottom, spacing: 12) {
                    Button(action: { showingPicker = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                            .frame(width: 32, height: 32)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }
                    .padding(.bottom, 6)
                    
                    TextField("iMessage", text: $inputText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    
                    if !inputText.isEmpty || selectedImage != nil {
                        Button(action: {
                            manager.sendMessage(inputText, with: selectedImage, to: sessionId)
                            inputText = ""
                            selectedImage = nil
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.blue)
                        }
                        .padding(.bottom, 6)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPicker) { ImagePicker(image: $selectedImage) }
    }
}

// MARK: - 5. iMessage 风格气泡
struct MessageBubble: View {
    let message: ChatMessage
    var isUser: Bool { message.role == .user }
    
    var body: some View {
        HStack {
            if isUser { Spacer() }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                if let img = message.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220)
                        .cornerRadius(16)
                }
                
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.body)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(isUser ? Color.blue : Color(.systemGray5))
                        .foregroundColor(isUser ? .white : .primary)
                        // 利用 iOS 16 的不规则圆角，制作 iMessage 的“小尾巴”效果
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 18,
                                bottomLeadingRadius: isUser ? 18 : 4,
                                bottomTrailingRadius: isUser ? 4 : 18,
                                topTrailingRadius: 18
                            )
                        )
                }
            }
            
            if !isUser { Spacer() }
        }
    }
}

// MARK: - 6. 极致安全的图片选择器
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController(); p.delegate = context.coordinator; return p
    }
    func updateUIViewController(_ ui: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ p: ImagePicker) { parent = p }
        func imagePickerController(_ p: UIImagePickerController, didFinishPickingMediaWithInfo i: [UIImagePickerController.InfoKey : Any]) {
            parent.image = i[.originalImage] as? UIImage; p.dismiss(animated: true)
        }
    }
}
