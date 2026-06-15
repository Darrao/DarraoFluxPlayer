import SwiftUI
import AVFoundation

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
            // Zone tactile invisible pour afficher/masquer les contrôles et gestes
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { toggleControls() }
                
                // Gestes de Double Tap (Avance/Recul 10s)
                #if os(iOS)
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { skipBackward() }
                    
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { skipForward() }
                }
                #endif
            }
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
            .focusable(!showControls)
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
                .padding(.bottom, 24)
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showSettings) {
            settingsPanelMobile
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
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
        HStack(spacing: 12) {
            // Play/Pause central (mobile)
            Button(action: { togglePlayPause() }) {
                Image(systemName: viewModel.player?.timeControlStatus == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(FPTheme.accentBlue))
            }
            .buttonStyle(.plain)

            // Indicateur de buffering
            if viewModel.isBuffering {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.8)
            }

            Spacer()

            // Bouton Live ou Recommencer selon le type de flux
            if viewModel.isLiveStream {
                if !viewModel.isDelayedMode {
                    goLiveButton
                }
            } else {
                restartButton
            }

            // Bouton Réglages (engrenage)
            settingsButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .glassBackground(radius: 26)
        #if os(tvOS)
        .focusSection()
        #endif
    }

    // =========================================================================
    // MARK: - Panneau de Réglages (Mobile Sheet)
    // =========================================================================

    private var settingsPanelMobile: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.1, green: 0.1, blue: 0.15).ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        settingGroup(title: "Qualité vidéo", icon: "tv.badge.wifi") {
                            qualitySettingSection
                        }
                        
                        settingGroup(title: "Vitesse de lecture", icon: "gauge.medium") {
                            speedSettingSection
                        }
                        
                        if viewModel.isLiveStream {
                            settingGroup(title: "Mode de lecture", icon: "bolt.fill") {
                                modeSettingSection
                            }
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Réglages FluxPlayer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { showSettings = false }
                        .fontWeight(.bold)
                }
            }
        }
    }

    private func settingGroup<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(FPTheme.accentBlue)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(FPTheme.subtleWhite)
            }
            content()
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // =========================================================================
    // MARK: - Boutons et Sections
    // =========================================================================

    private var qualitySettingSection: some View {
        FlowLayout(spacing: 10) {
            settingsOption("Auto", selected: viewModel.selectedBitrate == 0) { viewModel.selectedBitrate = 0 }
            settingsOption("HD", selected: viewModel.selectedBitrate == 1_500_000) { viewModel.selectedBitrate = 1_500_000 }
            settingsOption("SD", selected: viewModel.selectedBitrate == 800_000) { viewModel.selectedBitrate = 800_000 }
            settingsOption("LD", selected: viewModel.selectedBitrate == 400_000) { viewModel.selectedBitrate = 400_000 }
        }
    }

    private var speedSettingSection: some View {
        FlowLayout(spacing: 10) {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                let label = speed == 1.0 ? "Normal" : String(format: "%.2g×", speed)
                settingsOption(label, selected: viewModel.playbackSpeed == Float(speed)) {
                    viewModel.playbackSpeed = Float(speed)
                }
            }
        }
    }

    private var modeSettingSection: some View {
        HStack(spacing: 10) {
            settingsOption("Direct", icon: "bolt.fill", selected: !viewModel.isDelayedMode) {
                viewModel.isDelayedMode = false
            }
            settingsOption("Anti-saccades", icon: "tortoise.fill", selected: viewModel.isDelayedMode) {
                viewModel.isDelayedMode = true
            }
        }
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
                    .font(.system(size: 11, weight: .heavy))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(FPTheme.liveRed))
        }
        .buttonStyle(.plain)
    }

    private var restartButton: some View {
        Button(action: {
            viewModel.player?.seek(to: CMTime.zero)
            viewModel.player?.play()
            revealControls()
        }) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .heavy))
                Text("RECOMMENCER")
                    .font(.system(size: 11, weight: .heavy))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }

    private var settingsButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showSettings.toggle()
            }
            revealControls()
        }) {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    private func settingsOption(_ label: String, icon: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon { Image(systemName: icon).font(.system(size: 12)) }
                Text(label).font(.system(size: 14, weight: selected ? .bold : .medium))
            }
            .foregroundColor(selected ? .white : FPTheme.subtleWhite)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(selected ? FPTheme.accentBlue.opacity(0.8) : Color.white.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    // =========================================================================
    // MARK: - Logic (Gestures & Hide)
    // =========================================================================

    private func skipForward() {
        guard let player = viewModel.player else { return }
        let currentTime = player.currentTime()
        let newTime = CMTimeAdd(currentTime, CMTime(seconds: 10, preferredTimescale: 600))
        player.seek(to: newTime)
        showFeedback("forward")
    }

    private func skipBackward() {
        guard let player = viewModel.player else { return }
        let currentTime = player.currentTime()
        let newTime = CMTimeSubtract(currentTime, CMTime(seconds: 10, preferredTimescale: 600))
        player.seek(to: newTime)
        showFeedback("backward")
    }

    private func showFeedback(_ direction: String) {
        // Logique visuelle optionnelle pour le feedback (overlay temporaire)
        revealControls()
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.3)) { showControls.toggle() }
        if showControls && isFullScreen { scheduleHide() }
    }

    private func revealControls() {
        if !showControls { withAnimation(.easeInOut(duration: 0.25)) { showControls = true } }
        if isFullScreen { scheduleHide() }
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
        if player.timeControlStatus == .playing { player.pause() } else { player.play() }
        revealControls()
    }
}

/// Helper pour disposer les boutons en grille fluide
struct FlowLayout: View {
    var spacing: CGFloat
    let content: [AnyView]

    init<Data: Collection, Content: View>(spacing: CGFloat = 8, data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.spacing = spacing
        self.content = data.map { AnyView(content($0)) }
    }

    init<Content: View>(spacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        // Simplification pour l'exemple
        self.content = [AnyView(content())]
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<content.count, id: \.self) { index in
                content[index]
            }
        }
    }
}
