import SwiftUI
import os


struct CameraPicker: UIViewControllerRepresentable {
    
    var allowsEditing = false
    var onImage: (UIImage) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        
        let picker = UIImagePickerController()
        
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            assertionFailure("Camera source is not available.")
            AppLogger.ui.error("Camera source is not available.")
            return UIImagePickerController()
        }
        
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = allowsEditing
        picker.mediaTypes = ["public.image"]
        picker.delegate = context.coordinator
        
        return picker
    }
    
    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}
    
    class Coordinator: NSObject,
                       UINavigationControllerDelegate,
                       UIImagePickerControllerDelegate {
        
        let parent: CameraPicker
        
        init(_ parent: CameraPicker) {
            self.parent = parent
        }
        
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            
            if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage {
                parent.onImage(image)
            }
            
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
