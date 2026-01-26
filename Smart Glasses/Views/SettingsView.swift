//
//  SettingsView.swift
//  Smart Glasses
//
//  Settings and Meta glasses connection management
//

import SwiftUI
import MWDATCamera

/// Settings view for app configuration and glasses connection
struct SettingsView: View {
    @ObservedObject private var manager = WearablesManager.shared
    @AppStorage("autoSummarize") private var autoSummarize = true
    @AppStorage("speakSummaries") private var speakSummaries = false
    @AppStorage("distanceModeEnabled") private var distanceModeEnabled = true
    @AppStorage("multiPageModeEnabled") private var multiPageModeEnabled = false

    var body: some View {
        NavigationStack {
            List {
                // Meta Glasses Section
                Section {
                    // Connection status
                    HStack {
                        Label("Status", systemImage: "eyeglasses")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            Text(manager.deviceStatus)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Registration status
                    HStack {
                        Label("Registration", systemImage: "checkmark.shield")
                        Spacer()
                        Text(manager.registrationStateDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Stream status
                    HStack {
                        Label("Stream", systemImage: "video")
                        Spacer()
                        Text(streamStatusText)
                            .font(.subheadline)
                            .foregroundStyle(streamStatusColor)
                    }

                    // Camera permission
                    if let cameraStatus = manager.cameraStatus {
                        HStack {
                            Label("Camera", systemImage: "camera")
                            Spacer()
                            Text(cameraStatus)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Action buttons
                    Button {
                        manager.startRegistration()
                    } label: {
                        Label("Connect Glasses", systemImage: "link")
                    }

                    Button {
                        Task {
                            await manager.requestCameraPermission()
                        }
                    } label: {
                        Label("Request Camera Access", systemImage: "camera.badge.ellipsis")
                    }

                    // Stream control button
                    if manager.streamState == .streaming {
                        Button(role: .destructive) {
                            manager.stopStream()
                        } label: {
                            Label("Stop Stream", systemImage: "stop.circle")
                        }
                    } else if manager.registrationStateDescription == "Registered" {
                        Button {
                            manager.startStream()
                        } label: {
                            Label("Start Stream", systemImage: "play.circle")
                        }
                    }

                    Button(role: .destructive) {
                        manager.startUnregistration()
                    } label: {
                        Label("Disconnect Glasses", systemImage: "link.badge.plus")
                    }
                } header: {
                    Text("Meta Ray-Ban Glasses")
                } footer: {
                    Text("Connect your Meta Ray-Ban smart glasses to scan documents hands-free.")
                }

                // Scanning Settings
                Section {
                    Toggle(isOn: $distanceModeEnabled) {
                        Label("Distance Mode", systemImage: "arrow.up.left.and.arrow.down.right")
                    }

                    Toggle(isOn: $multiPageModeEnabled) {
                        Label("Multi-Page Mode", systemImage: "doc.on.doc")
                    }

                    Toggle(isOn: $autoSummarize) {
                        Label("Auto-Summarize", systemImage: "sparkles")
                    }

                    Toggle(isOn: $speakSummaries) {
                        Label("Speak Summaries", systemImage: "speaker.wave.2")
                    }
                } header: {
                    Text("Scanning")
                } footer: {
                    Text("Single-page mode auto-summarizes immediately after capture. Multi-page mode lets you scan multiple pages before generating one combined summary.")
                }

                // About Section
                Section {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com")!) {
                        Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                Task {
                    await manager.refreshRegistrationState()
                    await manager.refreshCameraPermissionStatus()
                }
            }
        }
    }

    private var statusColor: Color {
        if manager.deviceStatus.contains("Connected") {
            return .green
        } else if manager.registrationStateDescription == "Registered" {
            return .yellow
        } else {
            return .red
        }
    }

    private var streamStatusText: String {
        switch manager.streamState {
        case .streaming:
            return "Active"
        case .starting:
            return "Starting..."
        case .stopping:
            return "Stopping..."
        case .stopped:
            return "Stopped"
        @unknown default:
            return "Unknown"
        }
    }

    private var streamStatusColor: Color {
        switch manager.streamState {
        case .streaming:
            return .green
        case .starting, .stopping:
            return .orange
        case .stopped:
            return .secondary
        @unknown default:
            return .secondary
        }
    }
}

#Preview {
    SettingsView()
}
