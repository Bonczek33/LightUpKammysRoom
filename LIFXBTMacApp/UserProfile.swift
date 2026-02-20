//
//  UserProfile.swift
//  LIFXBTMacApp
//
//  Created by Tomasz Bak on 2/20/26.
//


//
//  ProfileStore.swift
//  LIFXBTMacApp
//
//  Data model and ObservableObject for multiple user profiles.
//
//  Each UserProfile stores the per-rider physiological values (name, date of
//  birth, FTP, weight) that drive zone calculations and W/kg display. Profiles
//  live in their own UserDefaults key so they survive a general settings reset
//  and can be managed independently of the rest of PersistedUserConfig.
//
//  When the active profile changes, ProfileStore posts
//  Notification.Name.activeProfileDidChange. ContentView observes this and
//  calls UserConfigStore.applyProfile(_:) to push the new values into the
//  existing config pipeline — no other part of the app needs to change.
//
//  Persistence keys:
//    "lifx_bt_profiles_v1"        — JSON-encoded [UserProfile]
//    "lifx_bt_active_profile_v1"  — UUID string of the active profile
//

import Foundation
import SwiftUI

// MARK: - Notification

extension Notification.Name {
    /// Posted whenever the active profile changes (selection or field edit).
    /// Carries the new UserProfile in userInfo["profile"].
    static let activeProfileDidChange = Notification.Name("activeProfileDidChange")
}

// MARK: - UserProfile

struct UserProfile: Identifiable, Codable, Equatable, Hashable {
    var id:          UUID   = UUID()
    var name:        String
    var dateOfBirth: Date
    var ftp:         Int       // watts — Functional Threshold Power
    var weightKg:    Double    // body weight in kilograms

    // MARK: Derived

    var ageYears: Int {
        max(0, Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 0)
    }

    /// Age-predicted max HR: 220 − age, floor 80 bpm.
    var maxHR: Int { max(80, 220 - ageYears) }

    var weightLbs: Double { weightKg * 2.20462 }

    // MARK: Factory

    /// A sensible first-run default.
    static func makeDefault(named name: String = "Rider 1") -> UserProfile {
        var c = DateComponents(); c.year = 1989; c.month = 11; c.day = 14
        let dob = Calendar.current.date(from: c) ?? Date()
        return UserProfile(name: name, dateOfBirth: dob, ftp: 150, weightKg: 50.0)
    }
}

// MARK: - ProfileStore

/// Manages the list of user profiles and which one is currently active.
///
/// Inject as an `@EnvironmentObject` into SettingsView and any view that
/// needs profile data. Subscribe to `Notification.Name.activeProfileDidChange`
/// to react to selection or field changes in the rest of the app.
@MainActor
final class ProfileStore: ObservableObject {

    // MARK: Published state

    @Published private(set) var profiles:        [UserProfile] = []
    @Published private(set) var activeProfileID: UUID?

    /// The active profile — guaranteed non-nil once `profiles` is non-empty.
    var activeProfile: UserProfile? {
        guard let id = activeProfileID else { return profiles.first }
        return profiles.first { $0.id == id } ?? profiles.first
    }

    // MARK: Keys

    private let profilesKey = "lifx_bt_profiles_v1"
    private let activeIDKey = "lifx_bt_active_profile_v1"

    // MARK: Init

    init() {
        load()
        if profiles.isEmpty {
            let p = UserProfile.makeDefault()
            profiles        = [p]
            activeProfileID = p.id
            saveRaw()
        }
    }

    // MARK: - Mutations

    /// Add a new profile with the given name and make it the active profile.
    func addProfile(name: String) {
        let p = UserProfile.makeDefault(named: name)
        profiles.append(p)
        activeProfileID = p.id
        saveRaw()
        postActiveChanged(p)
    }

    /// Replace the stored copy of a profile (e.g. after the user edits fields).
    /// Posts `activeProfileDidChange` when the active profile is updated.
    func update(_ profile: UserProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        saveRaw()
        if profile.id == activeProfileID {
            postActiveChanged(profile)
        }
    }

    /// Delete a profile by ID. The last profile cannot be deleted.
    /// If the active profile is deleted, the first remaining profile becomes active.
    func delete(id: UUID) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
        if activeProfileID == id {
            activeProfileID = profiles.first?.id
            if let p = activeProfile { postActiveChanged(p) }
        }
        saveRaw()
    }

    /// Make a profile the active one. Posts `activeProfileDidChange`.
    func activate(id: UUID) {
        guard profiles.contains(where: { $0.id == id }), id != activeProfileID else { return }
        activeProfileID = id
        saveRaw()
        if let p = activeProfile { postActiveChanged(p) }
    }

    // MARK: - Persistence

    func load() {
        if let data    = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([UserProfile].self, from: data) {
            profiles = decoded
        }
        if let str  = UserDefaults.standard.string(forKey: activeIDKey),
           let uuid = UUID(uuidString: str),
           profiles.contains(where: { $0.id == uuid }) {
            activeProfileID = uuid
        } else {
            activeProfileID = profiles.first?.id
        }
    }

    private func saveRaw() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
        UserDefaults.standard.set(activeProfileID?.uuidString, forKey: activeIDKey)
    }

    // MARK: - Private helpers

    private func postActiveChanged(_ profile: UserProfile) {
        NotificationCenter.default.post(
            name: .activeProfileDidChange,
            object: nil,
            userInfo: ["profile": profile]
        )
    }
}