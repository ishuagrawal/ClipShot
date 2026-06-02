import Foundation

struct RemoveAnnotationCommand: EditorCommand {
    let annotation: Annotation
    let index: Int

    var displayName: String { "Delete annotation" }

    func apply(to document: inout EditorDocument) {
        document.annotations.removeAll { $0.id == annotation.id }
    }

    func revert(to document: inout EditorDocument) {
        let clampedIndex = min(max(index, 0), document.annotations.count)
        document.annotations.insert(annotation, at: clampedIndex)
    }
}
