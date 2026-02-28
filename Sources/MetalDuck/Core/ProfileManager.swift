import Foundation

@MainActor
final class ProfileManager {
    static let shared = ProfileManager()
    
    private let storageKey = "com.metalduck.profiles"
    private let activeProfileIdKey = "com.metalduck.activeProfileId"
    
    private(set) var profiles: [Profile] = []
    private(set) var activeProfileId: UUID
    
    var activeProfile: Profile {
        profiles.first(where: { $0.id == activeProfileId }) ?? profiles[1] // Default to Balanced if active not found
    }
    
    private init() {
        // Built-in profiles
        let performance = Profile(
            name: "Performance",
            settings: RenderSettings(
                upscalingAlgorithm: .nativeLinear,
                outputScale: 1.0,
                matchOutputResolution: true,
                samplingMode: .nearest,
                sharpness: 0.0,
                dynamicResolutionEnabled: true,
                dynamicScaleMinimum: 0.70,
                dynamicScaleMaximum: 1.0,
                targetPresentationFPS: 60,
                frameGenerationEnabled: false,
                frameGenerationMode: .x2
            ),
            capture: CaptureConfiguration(framesPerSecond: 30, queueDepth: 4),
            isBuiltIn: true
        )
        
        let balanced = Profile(
            name: "Balanced",
            settings: RenderSettings(
                upscalingAlgorithm: .metalFXSpatial,
                outputScale: 1.15,
                matchOutputResolution: true,
                samplingMode: .linear,
                sharpness: 0.12,
                dynamicResolutionEnabled: false,
                dynamicScaleMinimum: 1.0,
                dynamicScaleMaximum: 1.0,
                targetPresentationFPS: 60,
                frameGenerationEnabled: true,
                frameGenerationMode: .x2
            ),
            capture: CaptureConfiguration(framesPerSecond: 30, queueDepth: 5),
            isBuiltIn: true
        )
        
        let quality = Profile(
            name: "Quality",
            settings: RenderSettings(
                upscalingAlgorithm: .metalFXSpatial,
                outputScale: 1.35,
                matchOutputResolution: false,
                samplingMode: .linear,
                sharpness: 0.22,
                dynamicResolutionEnabled: false,
                dynamicScaleMinimum: 1.0,
                dynamicScaleMaximum: 1.0,
                targetPresentationFPS: 60,
                frameGenerationEnabled: true,
                frameGenerationMode: .x2
            ),
            capture: CaptureConfiguration(framesPerSecond: 30, queueDepth: 6),
            isBuiltIn: true
        )
        
        // Load saved profiles or use defaults
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([Profile].self, from: data) {
            self.profiles = [performance, balanced, quality] + saved.filter { !$0.isBuiltIn }
        } else {
            self.profiles = [performance, balanced, quality]
        }
        
        // Restore active profile
        if let idString = UserDefaults.standard.string(forKey: activeProfileIdKey),
           let id = UUID(uuidString: idString),
           profiles.contains(where: { $0.id == id }) {
            self.activeProfileId = id
        } else {
            self.activeProfileId = balanced.id
        }
    }
    
    /// Selects a profile as the active one and persists the selection.
    func selectProfile(id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileId = id
        UserDefaults.standard.set(id.uuidString, forKey: activeProfileIdKey)
    }
    
    /// Creates a new custom profile with the given parameters and saves it.
    func createProfile(name: String, settings: RenderSettings, capture: CaptureConfiguration) -> Profile {
        let profile = Profile(name: name, settings: settings, capture: capture)
        profiles.append(profile)
        saveCustomProfiles()
        return profile
    }
    
    func updateActiveProfile(settings: RenderSettings? = nil, capture: CaptureConfiguration? = nil) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileId }) else { return }
        
        if let settings {
            profiles[index].settings = settings
        }
        if let capture {
            profiles[index].capture = capture
        }
        
        if !profiles[index].isBuiltIn {
            saveCustomProfiles()
        }
    }
    
    /// Renames a non-built-in profile.
    func renameProfile(id: UUID, newName: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }), !profiles[index].isBuiltIn else { return }
        profiles[index].name = newName
        saveCustomProfiles()
    }
    
    func deleteProfile(id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }), !profiles[index].isBuiltIn else { return }
        
        profiles.remove(at: index)
        if activeProfileId == id {
            activeProfileId = profiles[1].id // Default to Balanced
            UserDefaults.standard.set(activeProfileId.uuidString, forKey: activeProfileIdKey)
        }
        saveCustomProfiles()
    }
    
    func duplicateProfile(_ profile: Profile) -> Profile {
        let newName = "\(profile.name) Copy"
        return createProfile(name: newName, settings: profile.settings, capture: profile.capture)
    }
    
    private func saveCustomProfiles() {
        let custom = profiles.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
