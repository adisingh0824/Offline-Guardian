import SwiftUI
import CoreLocation
import AVFoundation
import UIKit
import Combine
import MessageUI

// MARK: - UserDefaults Keys
enum StorageKeys {
    static let contacts = "offlineGuardianContacts"
    static let message = "offlineGuardianMessage"
}

// MARK: - Global Contacts + Message Store (Offline Save)
class ContactsStore: ObservableObject {
    @Published var contacts: [String] = [] {
        didSet { saveContacts() }
    }

    @Published var sosMessage: String = "EMERGENCY! I need help. Please contact me immediately." {
        didSet { saveMessage() }
    }

    init() {
        loadContacts()
        loadMessage()
    }

    private func saveContacts() {
        UserDefaults.standard.set(contacts, forKey: StorageKeys.contacts)
    }

    private func loadContacts() {
        contacts = UserDefaults.standard.stringArray(forKey: StorageKeys.contacts) ?? []
    }

    private func saveMessage() {
        UserDefaults.standard.set(sosMessage, forKey: StorageKeys.message)
    }

    private func loadMessage() {
        sosMessage = UserDefaults.standard.string(forKey: StorageKeys.message)
        ?? "EMERGENCY! I need help. Please contact me immediately."
    }
}

// MARK: - Root View
struct ContentView: View {
    @StateObject private var store = ContactsStore()

    var body: some View {
        TabView {
            HomeView()
                .environmentObject(store)
                .tabItem { Label("SOS", systemImage: "exclamationmark.triangle.fill") }

            ContactsView()
                .environmentObject(store)
                .tabItem { Label("Contacts", systemImage: "person.2.fill") }

            SettingsView()
                .environmentObject(store)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

// MARK: - Home View (SOS)
struct HomeView: View {
    @EnvironmentObject var store: ContactsStore
    @StateObject private var locationManager = LocationManager()

    @State private var activated = false
    @State private var showComposer = false
    @State private var messageBody = ""

    // Countdown
    @State private var countdown = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 22) {

            Text("Offline Guardian")
                .font(.largeTitle)
                .bold()

            if countdown > 0 {
                Text("Sending SOS in \(countdown)...")
                    .font(.headline)
                    .foregroundColor(.orange)

                Button("Cancel SOS") {
                    cancelSOS()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(12)
            }

            Button {
                startSOSCountdown()
            } label: {
                Text(activated ? "ACTIVE" : "SOS")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 200, height: 200)
                    .background(activated ? Color.orange : Color.red)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Emergency SOS")

            Text("Long press to stop alarm/flash")
                .foregroundColor(.gray)
                .font(.footnote)
                .onLongPressGesture {
                    stopAlarmAndFlash()
                }

            if store.contacts.isEmpty {
                Text("⚠️ Add emergency contacts first")
                    .foregroundColor(.red)
            } else {
                Text("Contacts: \(store.contacts.count)")
                    .foregroundColor(.gray)
            }

            Text("Works without internet")
                .foregroundColor(.gray)
        }
        .padding()
        .sheet(isPresented: $showComposer) {
            MessageComposerView(recipients: store.contacts, bodyText: messageBody)
        }
    }

    // MARK: - Countdown start
    func startSOSCountdown() {
        if store.contacts.isEmpty {
            HapticManager.emergencyTap()
            return
        }

        activated = true
        countdown = 5
        HapticManager.emergencyTap()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            if countdown > 1 {
                countdown -= 1
            } else {
                t.invalidate()
                countdown = 0
                triggerSOS()
            }
        }
    }

    func cancelSOS() {
        timer?.invalidate()
        timer = nil
        countdown = 0
        activated = false
        stopAlarmAndFlash()
    }

    // MARK: - Trigger SOS
    func triggerSOS() {
        locationManager.requestLocation()

        // Start alarm + flash blink
        SOSSoundManager.shared.playAlarm()
        FlashBlinkManager.shared.startBlinking()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let loc = locationManager.lastLocation

            let locationText = loc != nil
            ? "Lat: \(loc!.coordinate.latitude), Lon: \(loc!.coordinate.longitude)"
            : "Location unavailable"

            let mapLink = loc != nil
            ? "https://maps.google.com/?q=\(loc!.coordinate.latitude),\(loc!.coordinate.longitude)"
            : ""

            messageBody = """
            \(store.sosMessage)

            My last known location:
            \(locationText)

            \(mapLink)
            """

            if MFMessageComposeViewController.canSendText() {
                showComposer = true
            }
        }
    }

    func stopAlarmAndFlash() {
        activated = false
        SOSSoundManager.shared.stopAlarm()
        FlashBlinkManager.shared.stopBlinking()
    }
}

// MARK: - Contacts View
struct ContactsView: View {
    @EnvironmentObject var store: ContactsStore
    @State private var newContact = ""

    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    TextField("Enter phone number", text: $newContact)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.phonePad)

                    Button("Add") {
                        let trimmed = newContact.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            store.contacts.append(trimmed)
                            newContact = ""
                        }
                    }
                }
                .padding()

                List {
                    ForEach(store.contacts, id: \.self) { contact in
                        Text(contact)
                    }
                    .onDelete { indexSet in
                        store.contacts.remove(atOffsets: indexSet)
                    }
                }
            }
            .navigationTitle("Emergency Contacts")
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var store: ContactsStore

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("SOS Message")) {
                    TextEditor(text: $store.sosMessage)
                        .frame(height: 110)
                }

                Section(header: Text("Privacy")) {
                    Text("Offline Guardian stores all data on your device. No data is collected or shared online.")
                        .font(.footnote)
                }

                Section(header: Text("About")) {
                    Text("Offline Guardian is an offline-first safety app designed for emergency situations where internet connectivity may not be available.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var lastLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
    }

    func requestLocation() {
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.first
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error:", error.localizedDescription)
    }
}

// MARK: - SMS Composer View
struct MessageComposerView: UIViewControllerRepresentable {
    var recipients: [String]
    var bodyText: String
    @Environment(\.presentationMode) var presentationMode

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        var parent: MessageComposerView
        init(_ parent: MessageComposerView) { self.parent = parent }

        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true) {
                self.parent.presentationMode.wrappedValue.dismiss()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = recipients
        controller.body = bodyText
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
}

// MARK: - Alarm Sound Manager
class SOSSoundManager {
    static let shared = SOSSoundManager()
    private var player: AVAudioPlayer?

    func playAlarm() {
        guard let url = Bundle.main.url(forResource: "alarm", withExtension: "mp3") else {
            print("⚠️ alarm.mp3 not found in bundle")
            return
        }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.play()
    }

    func stopAlarm() {
        player?.stop()
    }
}

// MARK: - Flash Blink Manager
class FlashBlinkManager {
    static let shared = FlashBlinkManager()

    private var blinkTimer: Timer?
    private var isOn = false

    func startBlinking() {
        stopBlinking()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
            self.isOn.toggle()
            FlashManager.toggleFlash(on: self.isOn)
        }
    }

    func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        isOn = false
        FlashManager.toggleFlash(on: false)
    }
}

// MARK: - Flashlight Manager
class FlashManager {
    static func toggleFlash(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            print("Torch error:", error.localizedDescription)
        }
    }
}

// MARK: - Haptic Manager
class HapticManager {
    static func emergencyTap() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
}
