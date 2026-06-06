import SwiftUI

/// Combined document panel: the Layout (padding) section stacked over the Background
/// section, separated by a hairline. Replaces the former separate Layout and
/// Background tabs.
struct CanvasToolView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaddingToolView(state: state)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            BackgroundToolView(state: state)
        }
    }
}
