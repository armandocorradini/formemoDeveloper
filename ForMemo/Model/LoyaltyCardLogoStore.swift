
import Foundation

enum LoyaltyCardLogoStore {
    
    private static let folderName = "LoyaltyCardLogos"
    private static let cache = NSCache<NSString, NSData>()


    static var directoryURL: URL? {
        cloudDirectoryURL ?? localDirectoryURL
    }

    private static var cloudDirectoryURL: URL? {
        guard let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: "iCloud.corradini.armando.NewTask"
        ) else { return nil }
        let directory = containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static var localDirectoryURL: URL? {
        guard let localURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let directory = localURL.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    
    static func load(relativePath: String?) -> Data? {

        guard let relativePath else {
            return nil
        }

        if let cached = cache.object(forKey: relativePath as NSString) {
            return cached as Data
        }

        let cloudURL = cloudDirectoryURL?.appendingPathComponent(relativePath)
        let localURL = localDirectoryURL?.appendingPathComponent(relativePath)
        guard let fileURL = [cloudURL, localURL].compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }), let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return nil
        }

        if fileURL == localURL,
           let cloudURL,
           !FileManager.default.fileExists(atPath: cloudURL.path) {
            try? FileManager.default.copyItem(at: fileURL, to: cloudURL)
        }

        cache.setObject(data as NSData, forKey: relativePath as NSString)

        return data
    }
    
    static func loadLegacy(
        relativePath: String
    ) -> Data? {

        guard let localDirectory =
            FileManager.default
                .urls(
                    for: .documentDirectory,
                    in: .userDomainMask
                )
                .first?
                .appendingPathComponent(
                    folderName,
                    isDirectory: true
                )
        else {
            return nil
        }

        let fileURL = localDirectory
            .appendingPathComponent(relativePath)

        return try? Data(contentsOf: fileURL)
    }
    
    
    
    static func delete(relativePath: String?) {
        
        guard let relativePath else {
            return
        }
        
        cache.removeObject(
            forKey: relativePath as NSString
        )
        
        for directory in [cloudDirectoryURL, localDirectoryURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(relativePath))
        }
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
            
            cache.setObject(
                imageData as NSData,
                forKey: fileName as NSString
            )
            
            return fileName
            
        } catch {
            
            return nil
            
        }
    }
}
