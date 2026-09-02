import SwiftUI

struct SymbolImage: View {
    let name: String
    let size: CGFloat

    var body: some View {
        if NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil {
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: name)
                .font(.system(size: size, weight: .regular))
                .symbolRenderingMode(.hierarchical)
        }
    }
}
