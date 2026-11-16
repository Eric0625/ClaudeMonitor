import AppKit

/// The red capsule with the unread count in the menu bar.
enum UnreadBadge {
    /// A non-template image attachment, so that the menu bar does not tint it.
    static func attributedString(count: Int, font: NSFont) -> NSAttributedString {
        let digitFont = NSFont.monospacedDigitSystemFont(ofSize: (font.pointSize * 0.85).rounded(), weight: .semibold)
        let text = NSAttributedString(string: "\(count)", attributes: [
            .font: digitFont,
            .foregroundColor: NSColor.white,
        ])
        let textWidth = text.size().width
        let height = (digitFont.capHeight + 7).rounded()
        let width = max(height, (textWidth + 9).rounded())
        let capHeight = digitFont.capHeight
        let descender = digitFont.descender

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.systemRed.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            let baseline = (rect.height - capHeight) / 2
            text.draw(at: NSPoint(x: (rect.width - textWidth) / 2, y: baseline + descender))
            return true
        }
        image.isTemplate = false

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: ((font.capHeight - height) / 2).rounded(), width: width, height: height)
        return NSAttributedString(attachment: attachment)
    }
}
