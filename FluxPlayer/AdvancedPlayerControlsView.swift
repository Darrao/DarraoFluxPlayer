import SwiftUI

// =============================================================================
// MARK: - AdvancedPlayerControlsView
// Barre de contrôle overlay Glassmorphique avec auto-hide après 4s d'inactivité.
// Inclut : Qualité, Mode (Direct/Différé), Vitesse, Go Live, Panneau Réglages.
// =============================================================================

struct AdvancedPlayerControlsView: View {
    @ObservedObject var viewModel: PlayerViewModel
    let isFullScreen: Bool

    // Auto-hide : les contrôles disparaissent après quelques secondes
    @State private var showControls: Bool = true
    @State private var hideTask: DispatchWorkItem?

    // Panneau de réglages (slide-up)
    @State private var showSettings: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Zone tactile invisible pour afficher/masquer les contrôles
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }
                #if os(tvOS)
                .onPlayPauseCommand { togglePlayPause() }
                .onMoveCommand { _ in revealControls() }
                .onExitCommand { 
                    if showControls {
                        withAnimation { showControls = false; showSettings = false }
                    } else {
                        revealControls()
                    }
                }
                .focusable(!showControls) // Focusable only when hidden to catch swipes
                #endif

            if showControls {
                // Dégradé sombre en bas pour la lisibilité
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 140)
                    .allowsHitTesting(false)
                }
                .transition(.opacity)

                // Barre de contrôles principale
                VStack(spacing: 12) {
                    Spacer()
                    controlBar
                }
                .padding(.bottom, 16)
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Panneau de réglages (s'affiche par-dessus)
            if showSettings {
                settingsPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            if isFullScreen {
                scheduleHide()
            } else {
                showControls = true
            }
        }
    }

    // =========================================================================
    // MARK: - Barre de Contrôles
    // =========================================================================

    private var controlBar: some View {
        HStack(spacing: 10) {
            // Indicateur de buffering
            if viewModel.isBuffering {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
                    .transition(.opacity)
            }

            // Qualité rapide
            qualityMenuButton

            // Mode Direct / Différé
            modeMenuButton

            // Vitesse
            speedMenuButton

            Spacer()

            // Go Live
            goLiveButton

            // Bouton Réglages (engrenage)
            settingsButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassBackground(radius: 14)
        #if os(tvOS)
        .focusSection()
        #endif
    }

    // =========================================================================
    // MARK: - Boutons individuels
    // =========================================================================

    private var qualityMenuButton: some View {
        Menu {
            Button(action: { viewModel.selectedBitrate = 0; revealControls() }) {
                Label("Auto (Max)", systemImage: viewModel.selectedBitrate == 0 ? "checkmark" : "")
            }
            Button(action: { viewModel.selectedBitrate = 1_500_000; revealControls() }) {
                Label("Élevée (HD)", systemImage: viewModel.selectedBitrate == 1_500_000 ? "checkmark" : "")
            }
            Button(action: { viewModel.selectedBitrate = 800_000; revealControls() }) {
                Label("Moyenne (SD)", systemImage: viewModel.selectedBitrate == 800_000 ? "checkmark" : "")
            }
            Button(action: { viewModel.selectedBitrate = 400_000; revealControls() }) {
                Label("Basse (LD)", systemImage: viewModel.selectedBitrate == 400_000 ? "checkmark" : "")
            }
        } label: {
            controlPill(icon: "tv.badge.wifi", text: qualityLabel)
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
    }

    private var modeMenuButton: some View {
        Menu {
            Button(action: { viewModel.isDelayedMode = false; revealControls() }) {
                Label("Direct (Faible Latence)", systemImage: !viewModel.isDelayedMode ? "checkmark" : "")
            }
            Button(action: { viewModel.isDelayedMode = true; revealControls() }) {
                Label("Différé (Anti-saccades 60s)", systemImage: viewModel.isDelayedMode ? "checkmark" : "")
            }
        } label: {
            controlPill(
                icon: viewModel.isDelayedMode ? "tortoise.fill" : "bolt.fill",
                text: viewModel.isDelayedMode ? "Différé" : "Direct",
                tint: viewModel.isDelayedMode ? FPTheme.warningYellow : FPTheme.successGreen
            )
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
    }

    private var speedMenuButton: some View {
        Menu {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                Button(action: {
                    viewModel.playbackSpeed = Float(speed)
                    revealControls()
                }) {
                    Label(
                        speed == 1.0 ? "Normal (1×)" : "\(speed, specifier: "%.2g")×",
                        systemImage: viewModel.playbackSpeed == Float(speed) ? "checkmark" : ""
                    )
                }
            }
        } label: {
            let speedText = viewModel.playbackSpeed == 1.0 ? "1×" : String(format: "%.2g×", viewModel.playbackSpeed)
            controlPill(
                icon: "gauge.medium",
                text: speedText
            )
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
    }

    private var goLiveButton: some View {
        Button(action: {
            viewModel.isDelayedMode = false
            viewModel.seekToLive()
            revealControls()
        }) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 7, height: 7)
                Text("LIVE")
                    .font(.system(size: 13, weight: .heavy))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(FPTheme.liveRed)
            )
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
    }

    private var settingsButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showSettings.toggle()
            }
            revealControls()
        }) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.15)))
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
    }

    // =========================================================================
    // MARK: - Panneau de Réglages
    // =========================================================================

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsHeader
            qualitySettingSection
            speedSettingSection
            modeSettingSection
        }
        .padding(24)
        .frame(maxWidth: 500)
        .glassBackground(radius: 20)
        .padding(.horizontal, 20)
        .padding(.bottom, 80)
    }

    private var settingsHeader: some View {
        HStack {
            Text("Réglages")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showSettings = false
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(FPTheme.subtleWhite)
            }
            #if os(tvOS)
            .buttonStyle(.card)
            #else
            .buttonStyle(.plain)
            #endif
        }
    }

    private var qualitySettingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Qualité vidéo")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(FPTheme.subtleWhite)
            HStack(spacing: 10) {
                settingsOption("Auto", selected: viewModel.selectedBitrate == 0) {
                    viewModel.selectedBitrate = 0
                }
                settingsOption("HD", selected: viewModel.selectedBitrate == 1_500_000) {
                    viewModel.selectedBitrate = 1_500_000
                }
                settingsOption("SD", selected: viewModel.selectedBitrate == 800_000) {
                    viewModel.selectedBitrate = 800_000
                }
                settingsOption("LD", selected: viewModel.selectedBitrate == 400_000) {
                    viewModel.selectedBitrate = 400_000
                }
            }
        }
    }

    private var speedSettingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Vitesse de lecture")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(FPTheme.subtleWhite)
            HStack(spacing: 10) {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                    let label = speed == 1.0 ? "Normal" : String(format: "%.2g×", speed)
                    settingsOption(label, selected: viewModel.playbackSpeed == Float(speed)) {
                        viewModel.playbackSpeed = Float(speed)
                    }
                }
            }
        }
    }

    private var modeSettingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mode de lecture")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(FPTheme.subtleWhite)
            HStack(spacing: 10) {
                settingsOption("Direct", icon: "bolt.fill", selected: !viewModel.isDelayedMode) {
                    viewModel.isDelayedMode = false
                }
                settingsOption("Anti-saccades", icon: "tortoise.fill", selected: viewModel.isDelayedMode) {
                    viewModel.isDelayedMode = true
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Composants réutilisables
    // =========================================================================

    /// Pill label utilisée dans la barre de contrôle.
    private func controlPill(icon: String, text: String, tint: Color = .white) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.12))
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        )
    }

    /// Bouton de choix dans le panneau de réglages.
    private func settingsOption(_ label: String, icon: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(label)
                    .font(.system(size: 14, weight: selected ? .bold : .medium))
            }
            .foregroundColor(selected ? .white : FPTheme.subtleWhite)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(selected ? FPTheme.accentBlue.opacity(0.6) : Color.white.opacity(0.08))
            )
            .overlay(
                Capsule()
                    .stroke(selected ? FPTheme.accentBlue : Color.clear, lineWidth: 1.5)
            )
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
    }

    /// Label textuel court pour la qualité actuelle.
    private var qualityLabel: String {
        switch viewModel.selectedBitrate {
        case 0:           return "Auto"
        case 1_500_000:   return "HD"
        case 800_000:     return "SD"
        case 400_000:     return "LD"
        default:          return "Auto"
        }
    }

    // =========================================================================
    // MARK: - Auto-Hide Logic
    // =========================================================================
    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showControls.toggle()
        }
        if showControls && isFullScreen { scheduleHide() }
    }

    private func revealControls() {
        if !showControls {
            withAnimation(.easeInOut(duration: 0.25)) {
                showControls = true
            }
        }
        if isFullScreen {
            scheduleHide()
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        let task = DispatchWorkItem { [self] in
            withAnimation(.easeOut(duration: 0.5)) {
                showControls = false
                showSettings = false
            }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: task)
    }

    private func togglePlayPause() {
        guard let player = viewModel.player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
        revealControls()
    }
}
