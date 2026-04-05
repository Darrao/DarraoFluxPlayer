# FluxPlayer - Apple TV & iOS IPTV Player

FluxPlayer is a high-performance, modern IPTV streaming application designed specifically for **tvOS** (Apple TV) and **iOS**. It prioritizes a premium user experience with a focus-aware glassmorphic UI, smooth transitions, and advanced playback controls.

![FluxPlayer Preview](https://raw.githubusercontent.com/Darrao/DarraoFluxPlayer/main/Preview.png) _(Note: Placeholder for actual preview)_

## 🚀 Features

### 📺 Optimized for Apple TV

- **Focus-Aware Navigation**: A custom-built UI that follows tvOS design principles.
- **Siri Remote Support**: Full integration with the Siri Remote touchpad and buttons.
- **Side-by-Side Layout**: Quick access to favorites while managing playback.

### 🎥 Advanced Playback

- **Inline & Full-Screen Player**: Seamlessly switch between a dashboard view and an immersive full-screen experience.
- **Auto-Hide Controls**: (Full-Screen only) Controls disappear after 5 seconds of inactivity and reappear instantly on remote interaction.
- **Quality Control**: Manually select bitrate or use adaptive bitrate streaming.
- **Playback Speed**: Adjust speed from 0.5x up to 2.0x.
- **Timeshift (Anti-Saccades)**: A dedicated 45-second buffer mode to prevent stuttering on unstable live streams.

### ⭐ Favorites Management

- **Manual Add**: Directly paste a stream URL and save it with a custom name.
- **In-Player Management**: Add, rename, or remove favorites directly from the player interface without stopping the video.
- **Persistent Storage**: All settings and favorites are saved locally.

## 🛠 Tech Stack

- **SwiftUI**: 100% declarative UI.
- **AVKit / AVFoundation**: High-end media processing.
- **XcodeGen**: Project management via `project.yml`.

## 📦 Installation & Setup

1.  **Clone the repository**:

    ```bash
    git clone git@github.com:Darrao/DarraoFluxPlayer.git
    cd DarraoFluxPlayer
    ```

2.  **Generate the Xcode Project**:
    This project uses `xcodegen` to maintain a clean project structure.

    ```bash
    brew install xcodegen
    xcodegen generate
    ```

3.  **Open and Run**:
    ```bash
    open "Darrao Player.xcodeproj"
    ```
    Select the `FluxPlayerDarrao-tvOS` or `FluxPlayer-Darrao-iOS` scheme and run on your device or simulator.

## 📜 Repository Structure

- `project.yml`: The source of truth for the project configuration.
- `FluxPlayer/`: Core application source code.
- `Info-*.plist`: Platform-specific configuration templates.

## 🔐 Privacy & Security

FluxPlayer does not collect any user data. All favorites and stream URLs are stored locally on your device's `UserDefaults`.

---

Created by Darrao.
