import SwiftUI
import SwiftData


struct VaultGateView: View {

    @StateObject private var vaultLock = VaultLock.shared

    @Query(sort: \VaultItem.title)
    private var vaultItems: [VaultItem]

    private var requiresUnlock: Bool {
        !vaultItems.isEmpty
    }

    var body: some View {
        ZStack {

            AppGlassBackground()

            VaultView()
                .blur(radius: requiresUnlock && !vaultLock.isUnlocked ? 6 : 0)

            if requiresUnlock && !vaultLock.isUnlocked {

                VaultLockCoverView()
                    .interactiveDismissDisabled()
                    .zIndex(1000)
            }
        }
        .toolbar(
            (requiresUnlock && !vaultLock.isUnlocked) ? .hidden : .visible,
            for: .navigationBar
        )
        .animation(.snappy, value: vaultLock.isUnlocked)
    }
}
