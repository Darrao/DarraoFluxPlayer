import SwiftUI

// =============================================================================
// MARK: - FluxPlayer Theme
// Constantes de design et styles réutilisables (Glassmorphism / Apple HIG).
// =============================================================================

enum FPTheme {

    // MARK: - Couleurs

    /// Dégradé principal d'arrière-plan (bleu-noir profond).
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.06, green: 0.06, blue: 0.15),
            Color(red: 0.02, green: 0.02, blue: 0.07)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let cardBackground   = Color.white.opacity(0.07)
    static let cardBorder       = Color.white.opacity(0.12)
    static let accentBlue       = Color(red: 0.35, green: 0.55, blue: 1.0)
    static let liveRed          = Color(red: 0.95, green: 0.22, blue: 0.22)
    static let successGreen     = Color(red: 0.25, green: 0.88, blue: 0.45)
    static let warningYellow    = Color(red: 1.0, green: 0.82, blue: 0.25)
    static let subtleWhite      = Color.white.opacity(0.7)

    // MARK: - Dimensions

    static let cornerRadius: CGFloat      = 16
    static let smallCornerRadius: CGFloat  = 10
    static let cardPadding: CGFloat        = 16
    static let minTapTarget: CGFloat       = 44

    // MARK: - Focus & Touch

    static let focusScale: CGFloat         = 1.05
    static let focusShadowRadius: CGFloat  = 20
    static let touchScale: CGFloat         = 0.98 // Effet de pression sur mobile
}

// =============================================================================
// MARK: - Glassmorphic Background Modifier
// =============================================================================

struct GlassBackground: ViewModifier {
    var radius: CGFloat = FPTheme.cornerRadius

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(FPTheme.cardBorder, lineWidth: 0.5)
                }
            )
    }
}

extension View {
    /// Applique un fond Glassmorphique (blur + bordure subtile).
    func glassBackground(radius: CGFloat = FPTheme.cornerRadius) -> some View {
        modifier(GlassBackground(radius: radius))
    }
}

// =============================================================================
// MARK: - Focus-Aware Card Modifier (Apple TV)
// =============================================================================

struct FocusableCard: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isFocused ? FPTheme.focusScale : 1.0)
            .shadow(
                color: isFocused ? FPTheme.accentBlue.opacity(0.5) : Color.clear,
                radius: isFocused ? FPTheme.focusShadowRadius : 0
            )
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

extension View {
    /// Effet d'agrandissement + halo lumineux lorsqu'un élément reçoit le focus (tvOS).
    func focusableCard(isFocused: Bool) -> some View {
        modifier(FocusableCard(isFocused: isFocused))
    }
}

// =============================================================================
// MARK: - Pill Control Button (pour l'overlay du lecteur)
// =============================================================================

struct PillButton: View {
    let icon: String
    let label: String
    var foreground: Color = .white
    var background: Color = Color.white.opacity(0.15)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(background)
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
            )
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
    }
}

// =============================================================================
// MARK: - Section Header Style
// =============================================================================

struct SectionHeader: View {
    let title: String
    let icon: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(FPTheme.accentBlue.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .foregroundColor(FPTheme.accentBlue)
                    .font(.system(size: 14, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(FPTheme.subtleWhite)
                }
            }
            Spacer()
        }
    }
}
