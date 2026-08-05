import SwiftUI
import QuickLook

// MARK: - QuickLook

 struct QuickLookPreview: UIViewControllerRepresentable {
    
    @Environment(\.dismiss) private var dismiss
    
    let url: URL
    
    func makeUIViewController(context: Context) -> UINavigationController {
        
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        
        // 🔥 wrapper navigation
        let nav = UINavigationController(rootViewController: controller)
        

        controller.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: context.coordinator,
            action: #selector(Coordinator.close)
        )
        
        return nav
    }
    
    func updateUIViewController(
        _ uiViewController: UINavigationController,
        context: Context
    ) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, dismiss: dismiss)
    }
    
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        
        let url: URL
        let dismiss: DismissAction
        
        init(url: URL, dismiss: DismissAction) {
            self.url = url
            self.dismiss = dismiss
        }
        
        @objc func close() {
            dismiss() // 🔥 chiude lo sheet
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }
        
        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {

            guard FileManager.default.fileExists(atPath: url.path) else {
                return NSURL()
            }

            return url as NSURL
        }
    }
}
