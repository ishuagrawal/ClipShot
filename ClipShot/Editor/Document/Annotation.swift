import CoreGraphics
import Foundation

struct Annotation: Identifiable, Equatable {
    let id: UUID
    var kind: Kind

    init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }

    enum Kind: Equatable {
        case arrow(from: CGPoint, to: CGPoint, color: CGColor, weight: CGFloat)
        case rect(frame: CGRect, stroke: CGColor?, fill: CGColor?, weight: CGFloat, cornerRadius: CGFloat)
        case text(origin: CGPoint, string: String, fontSize: CGFloat, color: CGColor)
        case blur(frame: CGRect, radius: CGFloat)
    }
}
