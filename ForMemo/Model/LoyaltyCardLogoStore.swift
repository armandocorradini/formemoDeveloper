
import Foundation

enum LoyaltyCardLogoStore {
    
    private static let folderName = "LoyaltyCardLogos"
    private static let cache = NSCache<NSString, NSData>()


    static var directoryURL: URL? = {

        let fm = FileManager.default

//        if let containerURL = fm.url(
//            forUbiquityContainerIdentifier: "iCloud.corradini.armando.NewTask"
//        ) {
//
//            let directory = containerURL
//                .appendingPathComponent("Documents", isDirectory: true)
//                .appendingPathComponent(folderName, isDirectory: true)
//
//            if !fm.fileExists(atPath: directory.path) {
//
//                try? fm.createDirectory(
//                    at: directory,
//                    withIntermediateDirectories: true
//                )
//            }
//
//            return directory
//        }

        if let localURL = fm.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first {

            let directory = localURL
                .appendingPathComponent(folderName, isDirectory: true)

            if !fm.fileExists(atPath: directory.path) {

                try? fm.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            }

            return directory
        }

        return nil

    }()

    
    static func load(relativePath: String?) -> Data? {

        guard let relativePath,
              let directoryURL else {
            return nil
        }

        if let cached = cache.object(forKey: relativePath as NSString) {
            return cached as Data
        }

        let fileURL = directoryURL.appendingPathComponent(relativePath)

        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
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
        
        guard let relativePath,
              let directoryURL else {
            return
        }
        
        let fileURL = directoryURL.appendingPathComponent(relativePath)
        
        cache.removeObject(
            forKey: relativePath as NSString
        )
        
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
