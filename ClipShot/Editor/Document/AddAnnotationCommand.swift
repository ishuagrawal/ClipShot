import Foundation

struct AddAnnotationCommand: EditorCommand {
    let annotation: Annotation

    var displayName: String { "Add annotation" }

    func apply(to document: inout EditorDocument) {
        document.annotations.append(annotation)
    }

    func revert(to document: inout EditorDocument) {
        document.annotations.removeAll { $0.id == annotation.id }
    }
}
