# OnionBurn

OnionBurn is a Flutter-based ephemeral chat app that leverages Tor hidden services to create a peer-to-peer connection between your phone and a browser over the Tor network. This enables highly private, throwaway chat sessions. The app launches a temporary Tor hidden service on your device, exposes a local chat web interface, and allows direct, encrypted WebSocket chatting between your phone and any web browser accessing the Onion URL.

---

## Features

- **Ephemeral Tor Hidden Service:** Starts a Tor hidden service for your device with single-tap bootstrapping.
- **Peer-to-Peer Chat:** Secure messaging between your phone and a browser via Tor (uses WebSocket).
- **No Registration, No History:** Deletes chat and keys on session shutdown, maximizing privacy.
- **Web Browser Friendly:** The chat interface is an HTML+JavaScript page with modern UX.
- **Status Logging:** In-app logs keep you aware of Tor and session status.

---

## How It Works

1. **Start the App**: Launch the Flutter app. It automatically actions Tor startup and waits for it to be ready.
2. **Hidden Service Creation**: Once Tor is ready, the app spins up a local HTTP server and exposes it as a Tor hidden service.
3. **Share Onion URL**: The generated `.onion` address is displayed; share this with your intended peer. They can use Tor Browser or similar.
4. **P2P WebSocket Chat**: When your peer accesses the link, they get a browser-based chat interface. Messages are exchanged end-to-end using WebSockets (even if both peers are remote).
5. **Session Destroy**: When done, close the session; this will cleanly shut down Tor and purge hidden service keys.

---

## Setup Instructions

### Prerequisites

- **Flutter SDK** (3.x or newer recommended)
- **Dart** (compatible with your selected Flutter)
- **Tor app or binary**: The [`tor_hidden_service`](https://pub.dev/packages/tor_hidden_service) plugin manages Tor on your device.
- **A Tor-supporting phone or emulator** (Android preferred; iOS support is experimental and may require additional setup)
- **Package dependencies:**
  - `flutter`
  - `tor_hidden_service`

### Getting Started

1. **Clone or Download:**  
   Grab the source for this project and place the Dart code into your Flutter project's `lib/main.dart`.

2. **Add Dependencies:**  
   Add dependencies in your `pubspec.yaml`:
   ```yaml
   dependencies:
     flutter:
       sdk: flutter
     tor_hidden_service: ^latest_version
   ```

3. **Android Extra Setup:**  
   - Android:  
     Ensure internet permission is granted in your `AndroidManifest.xml`:
     ```xml
     <uses-permission android:name="android.permission.INTERNET" />
     ```
   - For Tor binary, the `tor_hidden_service` package will install it automatically.

4. **iOS Extra Setup:**  
   - iOS requires additional configuration to run Tor and bind local ports. See package documentation.

5. **Run The App:**  
   ```bash
   flutter run
   ```
   Boot the app on your device/emulator.  
   Once Tor finishes bootstrapping, you’ll get an Onion URL.

6. **Connect a Browser Peer:**  
   Send the Onion link (`http://xyz.onion`) to a friend.  
   The peer should open it in Tor Browser on desktop or mobile.  
   The browser will show the chat interface and connect via WebSocket.

---

## Security & Privacy Notes

- **Ephemeral keys:** Onion service keys are deleted at session end.
- **Single peer:** Only one browser can connect per chat session.
- **Tor Isolation:** All traffic traverses Tor for privacy.
- **No message retention:** Messages are never stored on disk.

---

## Folder & File Structure

- `main.dart`: Contains all code (Flutter UI, Tor logic, local server, chat protocol).
- HTML+JS for the browser interface is embedded as a constant inside `main.dart`.

---

## Code Highlights

- Uses [tor_hidden_service](https://pub.dev/packages/tor_hidden_service) for simple Tor lifecycle management.
- The chat interface uses HTML and browser-native WebSockets for instant messaging.
- Automatically detects Tor’s bootstrap status and Onion readiness.
- UI for sharing Onion address & live message logs.

---

## Example Workflow

1. Start the app (`flutter run`).
2. Wait for "Tor Ready" and Onion address display.
3. Share the Onion address.
4. Peer connects via Tor Browser, enters chat, can send/receive messages.
5. End session by clicking the 'trash' button to destroy chat and keys.

---

## Troubleshooting

- **Tor not bootstrapping?** Ensure you have a working internet connection and the Tor binary is installed.
- **Browser cannot connect?** Verify the peer uses a full Tor Browser. Plain browsers cannot open .onion links.
- **Session ends unexpectedly?** Only one browser peer is allowed per session to keep keys ephemeral.

---

## License

MIT License.  
See `LICENSE` file for details.

---

## Acknowledgements

- [Tor Project](https://www.torproject.org/)
- [tor_hidden_service Dart package](https://pub.dev/packages/tor_hidden_service)
- Flutter, Dart, and the open source community.

---

## Demo Screenshots

> Screen images and GIFs (Add here for full walkthrough if needed)

---

## Disclaimer

This is an educational privacy-focused chat demo app. Use at your own risk and for learning purposes only.
