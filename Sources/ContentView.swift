import SwiftUI
import UIKit

class GemmaInferenceManager: ObservableObject {
    @Published var chatHistory: [ChatMessage] = []
    @Published var isResponding: Bool = false
    private var personalizedMemoryContext: String = ""
    
    init() {}
    
    func sendMessage(_ text: String, with image: UIImage? = nil) {
        let userMessage = ChatMessage(role: .user, content: text, image: image)
        chatHistory.append(userMessage)
        isResponding = true
        
        if let originalImage = image {
            print("🚀 开始模拟端侧图片处理流程...")
            if let resizedImage = resizeImageForModel(originalImage, to: CGSize(width: 224, height: 224)) {
                print("✅ 图片已本地调整为 224x224 像素")
            }
        }
        
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 2.0)
            var responseText = "这是基于端侧大模型和你的记忆生成的回复。(云端编译测试版)"
            if image != nil {
                responseText = "Gemma 模拟多模态回复: 我看到你上传了图片 (已在手机上本地处理为 224x224 像素)。我已启用模拟的视觉编码器，并综合你的文本问题 “\(text)” 进行回复。我还需要真正的缝合版大模型文件才能准确识别图里的内容。不过，整个处理流程我们已经跑通了！"
            }
            DispatchQueue.main.async {
                self.chatHistory.append(ChatMessage(role: .model, content: responseText))
                self.isResponding = false
            }
        }
    }
    
    func clearMemory() {
        chatHistory.removeAll()
        chatHistory.append(ChatMessage(role: .system, content: "🧹 个性化记忆已成功清除。"))
    }
    
    private func resizeImageForModel(_ image: UIImage, to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resizedImage = UIGraphicsGetImageContextFromImage()
        UIGraphicsEndImageContext()
        if let jpegData = resizedImage?.jpegData(compressionQuality: 0.8) {
             return UIImage(data: jpegData)
        }
        return resizedImage
    }
}

enum ChatRole { case user, model, system }
struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let content: String
    let image: UIImage?
    init(role: ChatRole, content: String, image: UIImage? = nil) {
        self.role = role
        self.content = content
        self.image = image
    }
}

struct ContentView: View {
    @StateObject private var inferenceManager = GemmaInferenceManager()
    @State private var inputText: String = ""
    @State private var selectedUIImage: UIImage? = nil
    @State private var showingImagePicker = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(spacing: 12) {
                            ForEach(inferenceManager.chatHistory) { message in
                                MessageBubble(message: message)
                            }
                        }
                        .padding()
                        .onChange(of: inferenceManager.chatHistory.count) { _ in
                            withAnimation {
                                if let lastId = inferenceManager.chatHistory.last?.id {
                                    proxy.scrollTo(lastId, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                
                if let imagePreview = selectedUIImage {
                    HStack(alignment: .top) {
                        Image(uiImage: imagePreview)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .cornerRadius(10)
                            .clipped()
                        Button(action: {
                            selectedUIImage = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.gray.opacity(0.15))
                    .transition(.move(edge: .bottom))
                }
                
                HStack {
                    Button(action: {
                        showingImagePicker = true
                    }) {
                        Image(systemName: "plus")
                            .font(.title3)
                            .padding(10)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .sheet(isPresented: $showingImagePicker) {
                        ImagePicker(image: $selectedUIImage)
                    }
                    
                    TextField("输入消息...", text: $inputText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button(action: {
                        guard !inputText.isEmpty || selectedUIImage != nil else { return }
                        inferenceManager.sendMessage(inputText, with: selectedUIImage)
                        inputText = ""
                        selectedUIImage = nil
                    }) {
                        Image(systemName: "paperplane.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .padding(10)
                            .background((inputText.isEmpty && selectedUIImage == nil) ? Color.gray : Color.blue)
                            .clipShape(Circle())
                    }
                    .disabled(inferenceManager.isResponding || (inputText.isEmpty && selectedUIImage == nil))
                }
                .padding()
            }
            .navigationTitle("Gemma Edge 1.0")
            .navigationBarItems(trailing: Button(action: {
                inferenceManager.clearMemory()
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            })
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 5) {
                if let imageInMsg = message.image {
                    Image(uiImage: imageInMsg)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .cornerRadius(10)
                        .padding(5)
                        .background(bubbleColor(for: message.role))
                        .cornerRadius(10)
                }
                if !message.content.isEmpty {
                    Text(message.content)
                        .padding(10)
                        .background(bubbleColor(for: message.role))
                        .foregroundColor(message.role == .system ? .gray : .white)
                        .cornerRadius(10)
                }
            }
            if message.role == .model || message.role == .system { Spacer() }
        }
    }
    func bubbleColor(for role: ChatRole) -> Color {
        switch role {
        case .user: return .blue
        case .model: return .green
        case .system: return .clear
        }
    }
}

// 🚀 核心降维修改：换用最古老、最无懈可击的原生引擎
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true)
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
