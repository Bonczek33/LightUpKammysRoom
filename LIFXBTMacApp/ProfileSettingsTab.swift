//
//  Settings+Profile.swift
//  LIFXBTMacApp
//
//  Profile Settings tab — create, edit, select, and delete rider profiles.
//
//  Layout: a fixed-width sidebar lists all profiles; the right panel shows
//  the editor for whichever profile is selected in the list. The active
//  profile (used by the app for zone/W-kg calculations) is indicated by a
//  filled person icon and bold name.  Any profile can be edited; only the
//  active profile feeds into live calculations.
//
//  The tab owns no PersistedUserConfig fields directly. It writes through
//  ProfileStore, which posts Notification.Name.activeProfileDidChange when
//  relevant — ContentView observes that and calls UserConfigStore.applyProfile.
//

import SwiftUI

// MARK: - Profile Settings Tab

struct ProfileSettingsTab: View {
    @EnvironmentObject var profiles: ProfileStore

    /// Which profile is selected in the sidebar (for editing).
    /// Defaults to the active profile; nil only briefly during deletions.
    @State private var selectedID: UUID? = nil

    /// Controls the "add profile" name-entry sheet.
    @State private var showingAddSheet  = false
    @State private var newProfileName   = ""

    /// Controls the delete-confirmation alert.
    @State private var pendingDeleteID: UUID? = nil

    // Resolve the sidebar selection to a profile, falling back to the active one.
    private var selectedProfile: UserProfile? {
        if let id = selectedID, let p = profiles.profiles.first(where: { $0.id == id }) { return p }
        return profiles.activeProfile
    }

    var body: some View {
        HSplitView {
            // ── Sidebar ───────────────────────────────────────────────────
            profileSidebar
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)

            // ── Editor ────────────────────────────────────────────────────
            Group {
                if let profile = selectedProfile {
                    ProfileEditorView(
                        profile: profile,
                        isActive: profile.id == profiles.activeProfileID,
                        onActivate: { profiles.activate(id: profile.id) },
                        onSave:     { profiles.update($0) }
                    )
                    // Force SwiftUI to destroy and recreate the editor (resetting
                    // all @State) whenever the selected profile changes identity.
                    .id(selectedID)
                } else {
                    Text("Select a profile")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 400)
        }
        .onAppear {
            // Select the active profile by default
            if selectedID == nil { selectedID = profiles.activeProfileID }
        }
        // Add profile sheet
        .sheet(isPresented: $showingAddSheet) {
            AddProfileSheet(name: $newProfileName) {
                let trimmed = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                let name    = trimmed.isEmpty ? "New Rider" : trimmed
                profiles.addProfile(name: name)
                selectedID    = profiles.activeProfileID
                newProfileName = ""
            }
        }
        // Delete confirmation
        .alert("Delete Profile?", isPresented: Binding(
            get: { pendingDeleteID != nil },
            set: { if !$0 { pendingDeleteID = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteID {
                    if selectedID == id { selectedID = nil }
                    profiles.delete(id: id)
                    // Re-select active after deletion
                    if selectedID == nil { selectedID = profiles.activeProfileID }
                }
                pendingDeleteID = nil
            }
        } message: {
            if let id  = pendingDeleteID,
               let name = profiles.profiles.first(where: { $0.id == id })?.name {
                Text("\"\(name)\" will be permanently removed. This cannot be undone.")
            }
        }
    }

    // MARK: Sidebar

    @ViewBuilder
    private var profileSidebar: some View {
        VStack(spacing: 0) {
            List(profiles.profiles, selection: $selectedID) { profile in
                ProfileRowView(
                    profile:  profile,
                    isActive: profile.id == profiles.activeProfileID
                )
                .tag(profile.id)
                .contextMenu {
                    Button("Activate") { profiles.activate(id: profile.id) }
                        .disabled(profile.id == profiles.activeProfileID)
                    Divider()
                    Button("Delete", role: .destructive) { pendingDeleteID = profile.id }
                        .disabled(profiles.profiles.count <= 1)
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Toolbar: add / delete
            HStack {
                Button {
                    newProfileName = ""
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add a new profile")

                Button {
                    if let id = selectedID ?? profiles.activeProfileID {
                        pendingDeleteID = id
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(profiles.profiles.count <= 1)
                .help("Delete selected profile")

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Profile Row

private struct ProfileRowView: View {
    let profile:  UserProfile
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isActive ? "person.fill" : "person")
                .foregroundColor(isActive ? .accentColor : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    .fontWeight(isActive ? .semibold : .regular)
                    .lineLimit(1)

                Text("FTP \(profile.ftp) W · \(profile.ageYears) y/o")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if isActive {
                Spacer()
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Profile Editor

private struct ProfileEditorView: View {
    // Working copy of the profile being edited.
    @State private var draft: UserProfile

    // String buffers for the numeric fields.
    // We parse on commit rather than using a NumberFormatter binding so that
    // partial input (e.g. clearing the field to type a new value) doesn't
    // get rejected or cause re-entrant onChange loops.
    @State private var ftpText:    String
    @State private var weightText: String

    let isActive:   Bool
    let onActivate: () -> Void
    let onSave:     (UserProfile) -> Void

    init(profile: UserProfile, isActive: Bool,
         onActivate: @escaping () -> Void,
         onSave:     @escaping (UserProfile) -> Void) {
        _draft       = State(initialValue: profile)
        _ftpText     = State(initialValue: "\(profile.ftp)")
        _weightText  = State(initialValue: String(format: "%.1f", profile.weightKg))
        self.isActive   = isActive
        self.onActivate = onActivate
        self.onSave     = onSave
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── Header ───────────────────────────────────────────────
                HStack(alignment: .firstTextBaseline) {
                    Text(draft.name.isEmpty ? "Unnamed" : draft.name)
                        .font(.title2).fontWeight(.semibold)
                    Spacer()
                    if !isActive {
                        Button("Set as Active") { onActivate() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    } else {
                        Label("Active Profile", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }

                Divider()

                // ── Identity ─────────────────────────────────────────────
                GroupBox(label: Text("Identity").font(.subheadline)) {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Name:")
                                .frame(width: 120, alignment: .trailing)
                            TextField("Rider name", text: $draft.name)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                                .onChange(of: draft.name) { _, _ in onSave(draft) }
                            Spacer()
                        }
                    }
                    .padding(8)
                }

                // ── Physiology ───────────────────────────────────────────
                GroupBox(label: Text("Physiology").font(.subheadline)) {
                    VStack(spacing: 12) {

                        // Date of birth
                        HStack {
                            Text("Date of Birth:")
                                .frame(width: 120, alignment: .trailing)
                            DatePicker("", selection: $draft.dateOfBirth,
                                       in: ...Date(), displayedComponents: [.date])
                                .labelsHidden()
                                .datePickerStyle(.field)
                                .frame(width: 140)
                                .help("Used to calculate age-predicted max HR (220 − age).")
                                .onChange(of: draft.dateOfBirth) { _, _ in onSave(draft) }
                            Spacer()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Age: \(draft.ageYears) yrs")
                                    .font(.caption).foregroundColor(.secondary)
                                Text("Max HR: \(draft.maxHR) bpm")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }

                        // FTP — plain String field, parsed on commit
                        HStack {
                            Text("FTP:")
                                .frame(width: 120, alignment: .trailing)
                            TextField("150", text: $ftpText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .help("Functional Threshold Power — used to calculate power training zones.")
                                .onSubmit { commitFTP() }
                                .onChange(of: ftpText) { _, _ in commitFTP() }
                            Text("watts").font(.caption).foregroundColor(.secondary)
                            Spacer()
                        }

                        // Weight — plain String field, parsed on commit
                        HStack {
                            Text("Weight:")
                                .frame(width: 120, alignment: .trailing)
                            TextField("50.0", text: $weightText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .help("Body weight — used to calculate W/kg in charts.")
                                .onSubmit { commitWeight() }
                                .onChange(of: weightText) { _, _ in commitWeight() }
                            Text("kg").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.1f lbs", draft.weightLbs))
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                }

                // ── Info banner when editing a non-active profile ────────
                if !isActive {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle").foregroundColor(.blue)
                        Text("Changes to this profile are saved but won't affect live calculations until you tap \"Set as Active\".")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color.blue.opacity(0.06))
                    .cornerRadius(8)
                }

                Spacer()
            }
            .padding(20)
        }
        // Safety net: if SwiftUI ever reuses this view instance for a different
        // profile (different UUID), resync the string buffers from the new draft.
        .onChange(of: draft.id) { _, _ in
            ftpText    = "\(draft.ftp)"
            weightText = String(format: "%.1f", draft.weightKg)
        }
    }

    // MARK: Commit helpers

    /// Parse ftpText → clamp → update draft → save.
    /// Ignores partial / empty input so the user can clear the field mid-edit.
    private func commitFTP() {
        guard let v = Int(ftpText.trimmingCharacters(in: .whitespaces)), v > 0 else { return }
        let clamped = max(50, min(500, v))
        guard draft.ftp != clamped else { return }
        draft.ftp = clamped
        onSave(draft)
    }

    private func commitWeight() {
        guard let v = Double(weightText.trimmingCharacters(in: .whitespaces)), v > 0 else { return }
        let clamped = max(30.0, min(200.0, v))
        guard draft.weightKg != clamped else { return }
        draft.weightKg = clamped
        onSave(draft)
    }
}

// MARK: - Add Profile Sheet

private struct AddProfileSheet: View {
    @Binding var name: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("New Profile")
                .font(.headline)

            TextField("Name (e.g. \"Kammy\")", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit { confirm() }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") { confirm() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320)
    }

    private func confirm() {
        onConfirm()
        dismiss()
    }
}
