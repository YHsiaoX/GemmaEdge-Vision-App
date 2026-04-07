import SwiftUI
import UIKit
import Foundation

class GemmaInferenceManager: ObservableObject {
    @Published var chatHistory: [ChatMessage] = []
    @Published var isResponding: Bool = false
    
    init() {}
    
    func sendMessage(_ text: String, with image: UIImage? = nil) {
        let userMessage = ChatMessage(role: .user, content: text, image: image)
        chatHistory.append(userMessage)
        isResponding = true
        
        if let originalImage = image {
            if let resizedImage = resizeImageForModel(originalImage, to: CGSize(width: 224, height: 224)) {
                print("Image resized locally")
            }
        }
        
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 2.0)
            var responseText = "这是基于端侧大模型生成的回复。"
            if image != nil {
                responseText = "Gemma 模拟多模态回复: 看到图片了，问题是 \"\(text)\"。目前已跑通端侧预处理流程，等待真实缝合版模型替换。"
            }
            DispatchQueue.main.async {
                self.chatHistory.append(ChatMessage(role: .model, content: responseText))
                self.isResponding = false
            }
        }
    }
    
    func clearMemory() {
        chatHistory.removeAll()
    }
    
    // 换用了苹果最新推荐的安全渲染引擎
    private func resizeImageForModel(_ image: UIImage, to size: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        if let jpegData = resizedImage.jpegData(compressionQuality: 0.8) {
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
                // 去掉了容易报错的 ScrollViewReader 和 onChange
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(inferenceManager.chatHistory) { message in
                            MessageBubble(message: message)
                        }
                    }
                    .padding()
                }
                
                if let imagePreview = selectedUIImage {
                    HStack {
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
                    .background(Color.gray.opacity(0.1))
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
                            .padding(10)
                            .background((inputText.isEmpty && selectedUIImage == nil) ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    .disabled(inferenceManager.isResponding || (inputText.isEmpty && selectedUIImage == nil))
                }
                .padding()
            }
            .navigationTitle("Gemma Edge")
            .navigationBarItems(trailing: Button(action: {
                inferenceManager.clearMemory()
            }) {
                Image(systemName: "trash").foregroundColor(.red)
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
                }
                if !message.content.isEmpty {
                    Text(message.content)
                        .padding(10)
                        .background(message.role == .user ? Color.blue : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            if message.role == .model || message.role == .system { Spacer() }
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // 严谨地补充了 UINavigationControllerDelegate 防止严格模式报错
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
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
