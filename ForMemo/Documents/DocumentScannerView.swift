import SwiftUI
import VisionKit
import AVFoundation
import os

@MainActor
struct DocumentScannerView: UIViewControllerRepresentable {
    
    @MainActor  let onComplete: ([UIImage]) -> Void
    
    @Environment(\.dismiss)
    private var dismiss
    
    // MARK: - Coordinator
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            onComplete: onComplete,
            dismiss: dismiss
        )
    }
    
    // MARK: - UIViewControllerRepresentable
    
    func makeUIViewController(context: Context) -> UIViewController {
        
        guard VNDocumentCameraViewController.isSupported else {
            
            let placeholder = UIViewController()
            
            DispatchQueue.main.async {
                dismiss()
            }
            
            return placeholder
        }
        
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        
        return scanner
    }
    
    func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {
        // Nothing to update
    }
}


// MARK: - Coordinator

extension DocumentScannerView {
    
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        
        @MainActor  let onComplete: ([UIImage]) -> Void
        private let dismiss: DismissAction
        
        init(
            onComplete: @escaping ([UIImage]) -> Void,
            dismiss: DismissAction
        ) {
            self.onComplete = onComplete
            self.dismiss = dismiss
        }
        
        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            
            var scannedImages: [UIImage] = []
            scannedImages.reserveCapacity(scan.pageCount)
            
            for pageIndex in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: pageIndex)
                scannedImages.append(image)
            }
            
            onComplete(scannedImages)
            
            dismiss()
        }
        
        func documentCameraViewControllerDidCancel(
            _ controller: VNDocumentCameraViewController
        ) {
            
            dismiss()
        }
        
        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            
            AppLogger.ui.error("Document scanner error: \(error.localizedDescription)")
            
            dismiss()
        }
    }
}
