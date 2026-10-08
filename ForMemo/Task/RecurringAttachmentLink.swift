import Foundation
import SwiftData

/// One logical propagation rule for a physical `TaskAttachment`.
///
/// The physical file remains owned by `TaskAttachment`. This model stores only
/// the recurrence-level rule saying that the attachment is available from a
/// given occurrence onward. The legacy scalar fields are intentionally retained
/// so the already-created SwiftData schema remains additive/compatible.
@Model
final class RecurringAttachmentLink {
    #Index<RecurringAttachmentLink>(
        [\.recurrenceID, \.propagationStartIndex],
        [\.attachmentID, \.recurrenceID]
    )

    var id: UUID = UUID()
    var attachmentID: UUID = UUID()

    // Compatibility/restore owner identifier. It is not a relationship.
    var taskID: UUID = UUID()

    var recurrenceID: UUID = UUID()
    var occurrenceIndex: Int = 1
    var propagationStartIndex: Int = 1
    var propagationEndIndex: Int?
    var isPropagationAnchor: Bool = true
    var isActive: Bool = true
    var createdAt: Date = Date()

    init(
        taskID: UUID,
        attachmentID: UUID,
        recurrenceID: UUID,
        occurrenceIndex: Int,
        propagationStartIndex: Int,
        propagationEndIndex: Int? = nil,
        isPropagationAnchor: Bool = true,
        isActive: Bool = true
    ) {
        self.taskID = taskID
        self.attachmentID = attachmentID
        self.recurrenceID = recurrenceID
        self.occurrenceIndex = occurrenceIndex
        self.propagationStartIndex = propagationStartIndex
        self.propagationEndIndex = propagationEndIndex
        self.isPropagationAnchor = isPropagationAnchor
        self.isActive = isActive
    }
}

@MainActor
enum RecurringAttachmentManager {

    @MainActor
    private final class ContextRuleCache {
        weak var context: ModelContext?
        var rulesByRecurrence: [UUID: [RecurringAttachmentLink]] = [:]
        var saveObserver: NSObjectProtocol?

        init(context: ModelContext) {
            self.context = context
            self.saveObserver = NotificationCenter.default.addObserver(
                forName: ModelContext.didSave,
                object: context,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.rulesByRecurrence.removeAll(keepingCapacity: true)
                }
            }
        }

        deinit {
            if let saveObserver {
                NotificationCenter.default.removeObserver(saveObserver)
            }
        }
    }

    private static var ruleCaches: [ObjectIdentifier: ContextRuleCache] = [:]

    private static func ruleCache(
        for context: ModelContext
    ) -> ContextRuleCache {
        let key = ObjectIdentifier(context)

        if let existing = ruleCaches[key], existing.context === context {
            return existing
        }

        ruleCaches = ruleCaches.filter { $0.value.context != nil }

        let cache = ContextRuleCache(context: context)
        ruleCaches[key] = cache
        return cache
    }

    static func invalidateRuleCache(
        for recurrenceID: UUID? = nil,
        in context: ModelContext
    ) {
        let cache = ruleCache(for: context)

        if let recurrenceID {
            cache.rulesByRecurrence.removeValue(forKey: recurrenceID)
        } else {
            cache.rulesByRecurrence.removeAll(keepingCapacity: true)
        }
    }

    enum DeletionScope {
        case thisOnly
        case thisAndFuture
        case global
    }

    struct LinkSnapshot: Codable {
        let linkID: UUID
        let taskID: UUID?
        let attachmentID: UUID?
        let recurrenceID: UUID?
        let occurrenceIndex: Int?
        let propagationStartIndex: Int?
        let propagationEndIndex: Int?
        let isPropagationAnchor: Bool
        let isActive: Bool
        let createdAt: Date
    }

    private static func allLinks(
        in context: ModelContext
    ) throws -> [RecurringAttachmentLink] {
        try context.fetch(
            FetchDescriptor<RecurringAttachmentLink>()
        )
    }

    /// Fetch only one recurrence using a simple scalar predicate. We avoid
    /// compound relationship predicates because the new model deliberately has
    /// no SwiftData relationship to `TaskAttachment`.
    private static func recurrenceLinks(
        for recurrenceID: UUID,
        in context: ModelContext
    ) throws -> [RecurringAttachmentLink] {
        let cache = ruleCache(for: context)

        if let cached = cache.rulesByRecurrence[recurrenceID] {
            return cached
        }

        let recurrenceIDValue = recurrenceID
        let fetched = try context.fetch(
            FetchDescriptor<RecurringAttachmentLink>(
                predicate: #Predicate<RecurringAttachmentLink> { link in
                    link.recurrenceID == recurrenceIDValue
                }
            )
        )

        cache.rulesByRecurrence[recurrenceID] = fetched
        return fetched
    }

    private static func fetchAttachment(
        id: UUID,
        in context: ModelContext
    ) throws -> TaskAttachment? {
        let attachmentID = id

        return try context.fetch(
            FetchDescriptor<TaskAttachment>(
                predicate: #Predicate<TaskAttachment> { attachment in
                    attachment.id == attachmentID
                }
            )
        ).first
    }

    /// Coalesces legacy per-occurrence records logically into one rule per
    /// attachment+recurrence without mutating the store. The earliest active
    /// start wins.
    private static func coalescedRules(
        _ links: [RecurringAttachmentLink]
    ) -> [RecurringAttachmentLink] {
        var byKey: [String: RecurringAttachmentLink] = [:]

        for link in links where link.isActive {
            let key = "\(link.attachmentID.uuidString)|\(link.recurrenceID.uuidString)"

            guard let existing = byKey[key] else {
                byKey[key] = link
                continue
            }

            if link.propagationStartIndex < existing.propagationStartIndex {
                byKey[key] = link
            }
        }

        return Array(byKey.values)
    }

    /// Collapses legacy records so that one active physical attachment has
    /// one active propagation rule per recurrence.
    static func normalizeRules(
        for recurrenceID: UUID,
        in context: ModelContext
    ) throws {
        let rawLinks = try recurrenceLinks(
            for: recurrenceID,
            in: context
        )

        var canonicalByAttachment: [UUID: RecurringAttachmentLink] = [:]

        for link in rawLinks {
            guard link.isActive else {
                context.delete(link)
                continue
            }

            guard let canonical = canonicalByAttachment[link.attachmentID] else {
                canonicalByAttachment[link.attachmentID] = link
                continue
            }

            if link.propagationStartIndex < canonical.propagationStartIndex {
                canonical.propagationStartIndex = link.propagationStartIndex
                canonical.occurrenceIndex = link.propagationStartIndex
                canonical.taskID = link.taskID
                context.delete(
                    canonicalByAttachment[link.attachmentID]!
                )
                canonicalByAttachment[link.attachmentID] = link
            } else {
                context.delete(link)
            }
        }

        invalidateRuleCache(for: recurrenceID, in: context)
    }

    /// Returns one logical active rule per attachment+recurrence for backup
    /// and maintenance operations.
    static func activeRules(
        in context: ModelContext
    ) throws -> [RecurringAttachmentLink] {
        coalescedRules(
            try allLinks(in: context)
        )
    }

    static func links(
        for task: TodoTask,
        in context: ModelContext
    ) -> [RecurringAttachmentLink] {
        guard let recurrenceID = task.recurrenceID,
              let occurrenceIndex = task.occurrenceIndex else {
            return []
        }

        guard let recurrenceLinks = try? recurrenceLinks(
            for: recurrenceID,
            in: context
        ) else {
            return []
        }

        return coalescedRules(recurrenceLinks).filter { link in
            occurrenceIndex >= link.propagationStartIndex &&
            (link.propagationEndIndex == nil ||
             occurrenceIndex <= (link.propagationEndIndex ?? occurrenceIndex))
        }
    }

    static func visibleAttachments(
        for task: TodoTask
    ) -> [TaskAttachment] {
        guard let context = task.modelContext else {
            return task.attachments ?? []
        }

        return visibleAttachments(
            for: task,
            in: context
        )
    }

    static func hasVisibleAttachments(
        for task: TodoTask,
        in context: ModelContext
    ) -> Bool {
        if !(task.attachments ?? []).isEmpty {
            return true
        }

        guard let recurrenceID = task.recurrenceID,
              let occurrenceIndex = task.occurrenceIndex else {
            return false
        }

        let rules = coalescedRules(
            (try? recurrenceLinks(
                for: recurrenceID,
                in: context
            )) ?? []
        )

        return rules.contains { rule in
            guard rule.isActive,
                  occurrenceIndex >= rule.propagationStartIndex else {
                return false
            }

            if let endIndex = rule.propagationEndIndex {
                return occurrenceIndex <= endIndex
            }

            return true
        }
    }

    static func visibleAttachments(
        for task: TodoTask,
        in context: ModelContext
    ) -> [TaskAttachment] {
        var result = task.attachments ?? []
        var seenIDs = Set<UUID>(
            result.map { $0.id }
        )

        guard let recurrenceID = task.recurrenceID,
              let occurrenceIndex = task.occurrenceIndex else {
            return result.sorted(by: attachmentSort)
        }

        let rules = coalescedRules(
            (try? recurrenceLinks(
                for: recurrenceID,
                in: context
            )) ?? []
        )

        let inheritedAttachmentIDs = Set(
            rules
                .filter { rule in
                    occurrenceIndex >= rule.propagationStartIndex &&
                    (rule.propagationEndIndex == nil ||
                     occurrenceIndex <= (rule.propagationEndIndex ?? occurrenceIndex)) &&
                    !seenIDs.contains(rule.attachmentID)
                }
                .map { $0.attachmentID }
        )

        guard !inheritedAttachmentIDs.isEmpty else {
            return result.sorted(by: attachmentSort)
        }

        // Fetch all inherited assets in one query instead of one query per
        // attachment. The predicate uses only the primitive UUID attribute.
        let attachmentIDs = Array(inheritedAttachmentIDs)
        let descriptor = FetchDescriptor<TaskAttachment>(
            predicate: #Predicate<TaskAttachment> { attachment in
                attachmentIDs.contains(attachment.id)
            }
        )

        let inheritedAttachments = (try? context.fetch(descriptor)) ?? []
        for attachment in inheritedAttachments {
            guard !seenIDs.contains(attachment.id) else { continue }
            seenIDs.insert(attachment.id)
            result.append(attachment)
        }

        return result.sorted(by: attachmentSort)
    }

    private static func attachmentSort(
        _ lhs: TaskAttachment,
        _ rhs: TaskAttachment
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Returns the active recurrence rule applicable to this occurrence.
    static func activeAnchor(
        for task: TodoTask,
        attachment: TaskAttachment
    ) -> RecurringAttachmentLink? {
        guard let recurrenceID = task.recurrenceID,
              let occurrenceIndex = task.occurrenceIndex,
              let context = task.modelContext else {
            return nil
        }

        return coalescedRules(
            (try? recurrenceLinks(
                for: recurrenceID,
                in: context
            )) ?? []
        ).first {
            $0.attachmentID == attachment.id &&
            occurrenceIndex >= $0.propagationStartIndex &&
            ($0.propagationEndIndex == nil ||
             occurrenceIndex <= ($0.propagationEndIndex ?? occurrenceIndex))
        }
    }

    static func attachmentIsPropagated(
        _ attachment: TaskAttachment,
        in context: ModelContext
    ) -> Bool {
        let attachmentID = attachment.id
        let descriptor = FetchDescriptor<RecurringAttachmentLink>(
            predicate: #Predicate<RecurringAttachmentLink> { link in
                link.attachmentID == attachmentID
            }
        )

        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Returns true when another materialized occurrence of a recurrence still
    /// uses this propagated attachment. The current task is excluded so an
    /// attachment is protected only while another occurrence actually remains.
    static func attachmentIsUsedByOtherOccurrences(
        _ attachment: TaskAttachment,
        excludingTaskID: UUID? = nil,
        in context: ModelContext
    ) -> Bool {
        let attachmentID = attachment.id
        let linkDescriptor = FetchDescriptor<RecurringAttachmentLink>(
            predicate: #Predicate<RecurringAttachmentLink> { link in
                link.attachmentID == attachmentID &&
                link.isActive == true
            }
        )

        guard let links = try? context.fetch(linkDescriptor),
              !links.isEmpty else {
            return false
        }

        var tasksByRecurrence: [UUID: [TodoTask]] = [:]

        for link in links {
            let recurrenceID = link.recurrenceID

            if tasksByRecurrence[recurrenceID] == nil {
                let recurrenceIDValue: UUID? = recurrenceID
                let taskDescriptor = FetchDescriptor<TodoTask>(
                    predicate: #Predicate<TodoTask> { task in
                        task.recurrenceID == recurrenceIDValue
                    }
                )

                tasksByRecurrence[recurrenceID] =
                    (try? context.fetch(taskDescriptor)) ?? []
            }

            guard let recurrenceTasks = tasksByRecurrence[recurrenceID] else {
                continue
            }

            if recurrenceTasks.contains(where: { occurrence in
                if let excludingTaskID, occurrence.id == excludingTaskID {
                    return false
                }

                guard let occurrenceIndex = occurrence.occurrenceIndex,
                      occurrenceIndex >= link.propagationStartIndex else {
                    return false
                }

                if let endIndex = link.propagationEndIndex,
                   occurrenceIndex > endIndex {
                    return false
                }

                return true
            }) {
                return true
            }
        }

        return false
    }

    static func inheritedAttachment(
        _ attachment: TaskAttachment,
        for task: TodoTask
    ) -> Bool {
        guard let link = activeAnchor(
            for: task,
            attachment: attachment
        ) else {
            return false
        }

        return task.attachments?.contains {
            $0.id == attachment.id
        } != true && link.isActive
    }

    /// Creates or updates exactly one logical propagation rule for each
    /// attachment+recurrence pair.
    static func configurePropagation(
        for attachments: [TaskAttachment],
        from task: TodoTask,
        in context: ModelContext
    ) throws {
        guard let recurrenceID = task.recurrenceID,
              let sourceIndex = task.occurrenceIndex,
              !attachments.isEmpty else {
            return
        }

        let existingLinks = try recurrenceLinks(
            for: recurrenceID,
            in: context
        )

        for attachment in attachments {
            let candidates = existingLinks.filter {
                $0.isActive &&
                $0.attachmentID == attachment.id
            }

            if let canonical = candidates.min(
                by: {
                    $0.propagationStartIndex <
                    $1.propagationStartIndex
                }
            ) {
                canonical.propagationStartIndex = min(
                    canonical.propagationStartIndex,
                    sourceIndex
                )
                canonical.occurrenceIndex = canonical.propagationStartIndex
                canonical.propagationEndIndex = nil
                canonical.isPropagationAnchor = true
                canonical.isActive = true

                // Preserve the physical owner's task whenever possible.
                canonical.taskID = attachment.task?.id ?? canonical.taskID

                // Remove duplicate legacy records for this same rule.
                for duplicate in candidates where duplicate.id != canonical.id {
                    context.delete(duplicate)
                }
            } else {
                let ownerID = attachment.task?.id ?? task.id

                context.insert(
                    RecurringAttachmentLink(
                        taskID: ownerID,
                        attachmentID: attachment.id,
                        recurrenceID: recurrenceID,
                        occurrenceIndex: sourceIndex,
                        propagationStartIndex: sourceIndex,
                        propagationEndIndex: nil,
                        isPropagationAnchor: true,
                        isActive: true
                    )
                )
            }
        }

        invalidateRuleCache(for: recurrenceID, in: context)
    }

    /// Compatibility no-op. Future occurrences resolve the rule dynamically;
    /// no per-occurrence link records are materialized.
    static func materializeLinks(
        for newTasks: [TodoTask],
        in context: ModelContext
    ) throws {
        _ = newTasks
        _ = context
    }

    static func remove(
        attachment: TaskAttachment,
        from task: TodoTask,
        scope: DeletionScope,
        in context: ModelContext
    ) throws {
        _ = task
        _ = scope

        try deleteLinks(
            for: attachment,
            in: context
        )
    }

    static func snapshotsForGlobalDeletion(
        attachment: TaskAttachment,
        in context: ModelContext
    ) throws -> [LinkSnapshot] {
        let attachmentID = attachment.id
        let descriptor = FetchDescriptor<RecurringAttachmentLink>(
            predicate: #Predicate<RecurringAttachmentLink> { link in
                link.attachmentID == attachmentID
            }
        )

        return try context.fetch(descriptor).map(snapshot)
    }

    static func deleteLinks(
        for attachment: TaskAttachment,
        in context: ModelContext
    ) throws {
        let attachmentID = attachment.id
        let descriptor = FetchDescriptor<RecurringAttachmentLink>(
            predicate: #Predicate<RecurringAttachmentLink> { link in
                link.attachmentID == attachmentID
            }
        )

        for link in try context.fetch(descriptor) {
            context.delete(link)
        }

        invalidateRuleCache(for: nil, in: context)
    }

    /// Shared source attachments are detached before `.cascade` can delete the
    /// task. The propagation rule remains independent of the task.
    @discardableResult
    static func detachSharedAttachmentsBeforeTaskDeletion(
        _ task: TodoTask,
        in context: ModelContext
    ) -> [TaskAttachment] {
        let shared = (task.attachments ?? []).filter {
            attachmentIsPropagated($0, in: context)
        }

        for attachment in shared {
            task.attachments?.removeAll {
                $0.id == attachment.id
            }
            attachment.task = nil
        }

        return shared
    }

    /// There are no per-occurrence links to delete. This method remains as a
    /// compatibility shim for existing callers.
    static func prepareLinksBeforeTaskDeletion(
        _ task: TodoTask,
        preserveAnchors: Bool,
        in context: ModelContext
    ) {
        _ = task
        _ = preserveAnchors
        _ = context
    }

    /// Stops a propagation at the specified last occurrence. This is used when
    /// a recurrence is ended/shortened so past occurrences retain the attachment
    /// while the current/future range does not.
    static func truncatePropagation(
        for recurrenceID: UUID,
        attachmentIDs: Set<UUID>,
        endingAt lastIndex: Int,
        in context: ModelContext
    ) throws {
        guard lastIndex >= 0 else {
            let links = try recurrenceLinks(
                for: recurrenceID,
                in: context
            )

            for link in links where
                attachmentIDs.isEmpty ||
                attachmentIDs.contains(link.attachmentID) {
                context.delete(link)
            }

            invalidateRuleCache(for: recurrenceID, in: context)
            return
        }

        let links = try recurrenceLinks(
            for: recurrenceID,
            in: context
        )

        for link in links where
            (attachmentIDs.isEmpty ||
             attachmentIDs.contains(link.attachmentID)) &&
            link.isActive {

            if link.propagationStartIndex > lastIndex {
                context.delete(link)
            } else {
                link.propagationEndIndex = lastIndex
            }
        }

        invalidateRuleCache(for: recurrenceID, in: context)
    }

    /// Removes duplicate/inapplicable rules left by older experimental builds.
    static func pruneUnreferencedRules(
        for recurrenceID: UUID,
        in context: ModelContext
    ) throws {
        let links = try recurrenceLinks(
            for: recurrenceID,
            in: context
        )

        let recurrenceIDValue: UUID? = recurrenceID
        let tasks = try context.fetch(
            FetchDescriptor<TodoTask>(
                predicate: #Predicate<TodoTask> { task in
                    task.recurrenceID == recurrenceIDValue
                }
            )
        )

        let remainingIndexes = Set(
            tasks.compactMap { $0.occurrenceIndex }
        )

        var canonicalByAttachment: [UUID: RecurringAttachmentLink] = [:]

        for link in links {
            guard link.isActive else {
                context.delete(link)
                continue
            }

            if let canonical = canonicalByAttachment[link.attachmentID] {
                if link.propagationStartIndex < canonical.propagationStartIndex {
                    canonicalByAttachment[link.attachmentID] = link
                    context.delete(canonical)
                } else {
                    context.delete(link)
                }
                continue
            }

            canonicalByAttachment[link.attachmentID] = link
        }

        for link in canonicalByAttachment.values {
            let hasOccurrence = remainingIndexes.contains {
                $0 >= link.propagationStartIndex &&
                (link.propagationEndIndex == nil ||
                 $0 <= (link.propagationEndIndex ?? $0))
            }

            if !hasOccurrence {
                context.delete(link)
            }
        }

        invalidateRuleCache(for: recurrenceID, in: context)
    }

    static func restoreDeletedTaskAttachments(
        for task: TodoTask,
        in context: ModelContext
    ) throws {
        guard let recurrenceID = task.recurrenceID,
              let occurrenceIndex = task.occurrenceIndex else {
            return
        }

        let links = try recurrenceLinks(
            for: recurrenceID,
            in: context
        )

        for link in coalescedRules(links) where
            link.isActive &&
            link.taskID == task.id &&
            link.propagationStartIndex <= occurrenceIndex &&
            (link.propagationEndIndex == nil ||
             occurrenceIndex <= (link.propagationEndIndex ?? occurrenceIndex)) {

            guard let attachment = try fetchAttachment(
                id: link.attachmentID,
                in: context
            ) else {
                continue
            }

            attachment.task = task

            if task.attachments == nil {
                task.attachments = []
            }

            if !(task.attachments ?? []).contains(where: {
                $0.id == attachment.id
            }) {
                task.attachments?.append(attachment)
            }
        }
    }

    static func encodedTaskLinkSnapshots(
        for task: TodoTask,
        in context: ModelContext
    ) -> Data? {
        guard let recurrenceID = task.recurrenceID else {
            return nil
        }

        do {
            let rules = coalescedRules(
                try recurrenceLinks(
                    for: recurrenceID,
                    in: context
                )
            )

            return try JSONEncoder().encode(
                rules.map(snapshot)
            )
        } catch {
            return nil
        }
    }

    static func encodedSnapshots(
        for attachment: TaskAttachment,
        in context: ModelContext
    ) -> Data? {
        do {
            let snapshots = try snapshotsForGlobalDeletion(
                attachment: attachment,
                in: context
            )

            return try JSONEncoder().encode(snapshots)
        } catch {
            return nil
        }
    }

    static func restoreTaskSnapshots(
        _ data: Data?,
        for task: TodoTask,
        in context: ModelContext
    ) {
        restoreSnapshots(
            data,
            preferredOwnerTask: task,
            preferredAttachment: nil,
            in: context
        )
    }

    static func restoreSnapshots(
        _ data: Data?,
        for attachment: TaskAttachment,
        ownerTask: TodoTask?,
        in context: ModelContext
    ) {
        restoreSnapshots(
            data,
            preferredOwnerTask: ownerTask,
            preferredAttachment: attachment,
            in: context
        )
    }

    static func restoreSnapshots(
        _ data: Data?,
        for attachment: TaskAttachment,
        in context: ModelContext
    ) {
        restoreSnapshots(
            data,
            preferredOwnerTask: nil,
            preferredAttachment: attachment,
            in: context
        )
    }

    private static func restoreSnapshots(
        _ data: Data?,
        preferredOwnerTask: TodoTask?,
        preferredAttachment: TaskAttachment?,
        in context: ModelContext
    ) {
        guard let data,
              let snapshots = try? JSONDecoder().decode(
                [LinkSnapshot].self,
                from: data
              ) else {
            return
        }

        var processedKeys = Set<String>()

        for snapshot in snapshots where snapshot.isActive {
            guard let recurrenceID = snapshot.recurrenceID,
                  let attachmentID = preferredAttachment?.id ??
                    snapshot.attachmentID else {
                continue
            }

            let startIndex =
                snapshot.propagationStartIndex ??
                snapshot.occurrenceIndex ??
                preferredOwnerTask?.occurrenceIndex ??
                1

            let ownerID =
                preferredOwnerTask?.id ??
                snapshot.taskID ??
                UUID()

            let key =
                "\(attachmentID.uuidString)|\(recurrenceID.uuidString)"

            guard processedKeys.insert(key).inserted else {
                continue
            }

            let existing = (try? recurrenceLinks(
                for: recurrenceID,
                in: context
            ))?.first {
                $0.attachmentID == attachmentID &&
                $0.isActive
            }

            let link = existing ?? RecurringAttachmentLink(
                taskID: ownerID,
                attachmentID: attachmentID,
                recurrenceID: recurrenceID,
                occurrenceIndex: startIndex,
                propagationStartIndex: startIndex,
                propagationEndIndex: snapshot.propagationEndIndex,
                isPropagationAnchor: true,
                isActive: true
            )

            if existing == nil {
                context.insert(link)
            }

            link.taskID = preferredOwnerTask?.id ?? link.taskID
            link.attachmentID = attachmentID
            link.recurrenceID = recurrenceID
            link.propagationStartIndex = min(
                link.propagationStartIndex,
                startIndex
            )
            link.occurrenceIndex = link.propagationStartIndex
            link.propagationEndIndex = snapshot.propagationEndIndex
            link.isPropagationAnchor = true
            link.isActive = true

            if let owner = preferredOwnerTask,
               let attachment = preferredAttachment {
                attachment.task = owner

                if owner.attachments == nil {
                    owner.attachments = []
                }

                if !(owner.attachments ?? []).contains(where: {
                    $0.id == attachment.id
                }) {
                    owner.attachments?.append(attachment)
                }
            }
        }

        if let recurrenceID = snapshots.compactMap({ $0.recurrenceID }).first {
            invalidateRuleCache(for: recurrenceID, in: context)
        }
    }

    private static func snapshot(
        _ link: RecurringAttachmentLink
    ) -> LinkSnapshot {
        LinkSnapshot(
            linkID: link.id,
            taskID: link.taskID,
            attachmentID: link.attachmentID,
            recurrenceID: link.recurrenceID,
            occurrenceIndex: link.propagationStartIndex,
            propagationStartIndex: link.propagationStartIndex,
            propagationEndIndex: link.propagationEndIndex,
            isPropagationAnchor: true,
            isActive: link.isActive,
            createdAt: link.createdAt
        )
    }
}

extension TodoTask {
    @MainActor
    var visibleTaskAttachments: [TaskAttachment] {
        RecurringAttachmentManager.visibleAttachments(
            for: self
        )
    }

    @MainActor
    var hasVisibleTaskAttachments: Bool {
        guard let context = modelContext else {
            return !(attachments ?? []).isEmpty
        }

        return RecurringAttachmentManager.hasVisibleAttachments(
            for: self,
            in: context
        )
    }
}
