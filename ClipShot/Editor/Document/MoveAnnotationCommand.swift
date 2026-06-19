import Foundation

enum AnnotationEditCoalescingKey: Equatable {
    case style
    case keyboardNudge
    case resize
}

struct MoveAnnotationCommand: EditorCommand {
    let id: UUID
    let from: Annotation.Kind
    let to: Annotation.Kind
    let coalescingKey: AnnotationEditCoalescingKey?

    init(
        id: UUID,
        from: Annotation.Kind,
        to: Annotation.Kind,
        coalescingKey: AnnotationEditCoalescingKey? = nil
    ) {
        self.id = id
        self.from = from
        self.to = to
        self.coalescingKey = coalescingKey
    }

    var displayName: String { "Move annotation" }

    func apply(to document: inout EditorDocument) {
        setKind(to, in: &document)
    }

    func revert(to document: inout EditorDocument) {
        setKind(from, in: &document)
    }

    func coalesce(with next: EditorCommand) -> EditorCommand? {
        guard let coalescingKey,
              let next = next as? MoveAnnotationCommand,
              next.id == id,
              next.coalescingKey == coalescingKey else { return nil }
        return MoveAnnotationCommand(id: id, from: from, to: next.to, coalescingKey: coalescingKey)
    }

    private func setKind(_ kind: Annotation.Kind, in document: inout EditorDocument) {
        guard let index = document.annotations.firstIndex(where: { $0.id == id }) else { return }
        document.annotations[index].kind = kind
    }
}
