import SwiftUI

/// The checkbox of a to-do that has people on it: one slice per assignee, in their colour.
///
/// A slice is pale until that person has ticked their part and solid once they have, so
/// "2 pairs of socks" for Alma and Vidar reads as half red, half green, filling in as each
/// of them packs. Slices run in assignee order: the first ends at twelve o'clock and the
/// rest follow round the dial, which puts two people on the left and right halves and a
/// third person on the bottom third.
struct AssigneePieCheckbox: View {
    let assignments: [Assignment]
    var diameter: CGFloat = 22

    var body: some View {
        let slices = assignments.compactMap { assignment in
            assignment.person.map { (color: $0.color, isDone: assignment.isDone) }
        }
        let isComplete = !slices.isEmpty && slices.allSatisfy(\.isDone)

        ZStack {
            ForEach(slices.indices, id: \.self) { index in
                PieSlice(index: index, count: slices.count)
                    .fill(slices[index].color.opacity(slices[index].isDone ? 1 : 0.2))
            }

            // Hairlines between the slices keep two similar colours apart.
            if slices.count > 1 {
                ForEach(slices.indices, id: \.self) { index in
                    PieSlice(index: index, count: slices.count)
                        .stroke(Color(.systemBackground), lineWidth: 1)
                }
            }

            Circle()
                .strokeBorder(Color.secondary.opacity(isComplete ? 0 : 0.6), lineWidth: 1.5)

            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: diameter * 0.45, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 0.5)
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.2), value: slices.map(\.isDone))
    }
}

/// Slice `index` of `count` equal slices. Angles are measured clockwise on screen from
/// twelve o'clock; slice 0 ends there.
private struct PieSlice: Shape {
    let index: Int
    let count: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        guard count > 1 else { return Path(ellipseIn: rect) }

        let sweep = 360.0 / Double(count)
        let start = sweep * Double(index - 1)
        // SwiftUI measures from three o'clock, and with y pointing down, increasing angles
        // already turn clockwise on screen — hence `clockwise: false`.
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(start - 90),
            endAngle: .degrees(start + sweep - 90),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
