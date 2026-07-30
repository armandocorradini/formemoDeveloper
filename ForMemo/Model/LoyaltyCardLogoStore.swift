
import Foundation

enum LoyaltyCardLogoStore {
    
    private static let folderName = "LoyaltyCardLogos"
    
    static var directoryURL: URL? {
        
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(folderName, isDirectory: true)
    }

    
    static func load(relativePath: String?) -> Data? {
        
        guard let relativePath,
              let directoryURL else {
            return nil
        }
        
        let fileURL = directoryURL.appendingPathComponent(relativePath)
        
        return try? Data(contentsOf: fileURL)
    }
    
    static func delete(relativePath: String?) {
        
        guard let relativePath,
              let directoryURL else {
            return
        }
        
        let fileURL = directoryURL.appendingPathComponent(relativePath)
        
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    static func load(
        asset: WalletAsset?
    ) -> Data? {
        
        guard let relativePath = asset?.relativePath else {
            return nil
        }
        
        return load(
            relativePath: relativePath
        )
    }
    
    static func delete(
        asset: WalletAsset?
    ) {
        
        delete(
            relativePath: asset?.relativePath
        )
    }
    
    
    
    
    static func save(
        imageData: Data
    ) -> String? {
        
        let fileExtension = "jpg"
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        
        guard
            let directoryURL
        else {
            return nil
        }
        
        do {
            
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            
            let fileURL = directoryURL.appendingPathComponent(fileName)
            
            try imageData.write(
                to: fileURL,
                options: .atomic
            )
            
            return fileName
            
        } catch {
            
            return nil
            
        }
    }
}
