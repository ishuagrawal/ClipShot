import SwiftUI

struct SelectToolView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        Group {
            switch state.selectedAnnotation?.kind {
            case .arrow:
                ArrowToolView(state: state)
            case .line:
                LineToolView(state: state)
            case .rect:
                RectangleToolView(state: state)
            case .text:
                TextToolView(state: state)
            default:
                EmptyView()
            }
        }
    }
}
