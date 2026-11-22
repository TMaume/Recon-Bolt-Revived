import SwiftUI

final class AppSettings: ObservableObject {
	static let defaultAccentColor = Color(.displayP3, red: 0.940, green: 0.019, blue: 0.311)
	
	@AppStorage("AppSettings.theme")
	var theme = Theme.system
	
	@AppStorage("AppSettings.customAccentColor")
	var customAccentColorComponents = ""
	
	// Interface settings (Valpaw parity)
	@AppStorage("LiveGameBox.shouldAutoShow")
	var autoOpenMatchDetails = false
	
	@AppStorage("vibrateOnMatchFound")
	var vibrateOnMatchFound = true
	
	@AppStorage("MatchList.isCompact")
	var isCompactListStyle = false
	
	@AppStorage("MatchList.autoDownload")
	var autoDownloadMatches = true
	
	@AppStorage("UserLabel.canCopy")
	var copyPlayerNames = true
	
	@AppStorage("Social.directProfileNavigation")
	var openProfileDirectly = false
	
	@AppStorage("Social.sortOfflineByLastSeen")
	var sortOfflineByLastSeen = true
	
	// Sign-in settings
	@AppStorage("Login.clearCookiesOnLogin")
	var clearWebSignInDataOnOpen = true
	
	// Auto-delete / Match retention settings
	@AppStorage("MatchRetention.maxAgeDays")
	var matchRetentionDays: Int = 14
	
	@AppStorage("MatchRetention.keepsOwnMatches")
	var keepsOwnMatches = true
	
	@AppStorage("MatchRetention.keepsBookmarkedMatches")
	var keepsBookmarkedMatches = true
	
	@AppStorage("MatchRetention.keepsUnlinkedMatches")
	var keepsUnlinkedMatches = false
	
	var hasCustomAccentColor: Bool {
		!customAccentColorComponents.isEmpty
	}
	
	var effectiveAccentColor: Color {
		let parts = customAccentColorComponents
			.split(separator: ",")
			.compactMap { Double($0) }
		guard parts.count == 3 else {
			return Self.defaultAccentColor
		}
		return Color(red: parts[0], green: parts[1], blue: parts[2])
	}
	
	var accentColorBinding: Binding<Color> {
		Binding(
			get: { self.effectiveAccentColor },
			set: { newValue in
				let uiColor = UIColor(newValue)
				var red: CGFloat = 0
				var green: CGFloat = 0
				var blue: CGFloat = 0
				var alpha: CGFloat = 0
				if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
					self.customAccentColorComponents = "\(Double(red)),\(Double(green)),\(Double(blue))"
				} else if let srgb = uiColor.cgColor.converted(to: .sRGBSpace, intent: .defaultIntent, options: nil),
				          let components = srgb.components, components.count >= 3 {
					self.customAccentColorComponents = "\(Double(components[0])),\(Double(components[1])),\(Double(components[2]))"
				}
				self.objectWillChange.send()
			}
		)
	}
	
	var matchRetentionLabel: String {
		matchRetentionDays <= 0 ? "Off" : "\(matchRetentionDays) Days"
	}
	
	func resetAccentColor() {
		customAccentColorComponents = ""
		objectWillChange.send()
	}
	
	func resetAll() {
		theme = .system
		customAccentColorComponents = ""
		autoOpenMatchDetails = false
		vibrateOnMatchFound = true
		isCompactListStyle = false
		autoDownloadMatches = true
		copyPlayerNames = true
		openProfileDirectly = false
		sortOfflineByLastSeen = true
		clearWebSignInDataOnOpen = true
		matchRetentionDays = 14
		keepsOwnMatches = true
		keepsBookmarkedMatches = true
		keepsUnlinkedMatches = false
		objectWillChange.send()
	}
	
	enum Theme: String, Hashable, Codable, CaseIterable {
		case system
		case light
		case dark
	}
}

extension AppSettings.Theme {
	var colorScheme: ColorScheme? {
		switch self {
		case .system:
			return nil
		case .light:
			return .light
		case .dark:
			return .dark
		}
	}
}
