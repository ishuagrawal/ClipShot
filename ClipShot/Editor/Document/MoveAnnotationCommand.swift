import Foundation

struct MoveAnnotationCommand: EditorCommand {
    let id: UUID
    let from: Annotation.Kind
    let to: Annotation.Kind

    var displayName: String { "Move annotation" }

    func apply(to document: inout EditorDocument) {
        setKind(to, in: &document)
    }

    func revert(to document: inout EditorDocument) {
        setKind(from, in: &document)
    }

    func coalesce(with next: EditorCommand) -> EditorCommand? {
        guard let next = next as? MoveAnnotationCommand, next.id == id else { return nil }
        return MoveAnnotationCommand(id: id, from: from, to: next.to)
    }

    private func setKind(_ kind: Annotation.Kind, in document: inout EditorDocument) {
        guard let index = document.annotations.firstIndex(where: { $0.id == id }) else { return }
        document.annotations[index].kind = kind
    }
}
