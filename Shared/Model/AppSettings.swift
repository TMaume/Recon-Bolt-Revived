import SwiftUI

final class AppSettings: ObservableObject {
	static let defaultAccentColor = Color(.displayP3, red: 0.940, green: 0.019, blue: 0.311)
	
	@AppStorage("AppSettings.theme")
	var theme = Theme.system
	
	@AppStorage("AppSettings.customAccentColor")
	var customAccentColorComponents = ""
	
	// Interface settings
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
		return Self.strictSRGBColor(red: parts[0], green: parts[1], blue: parts[2])
	}
	
	var accentColorBinding: Binding<Color> {
		Binding(
			get: {
				if self.hasCustomAccentColor {
					return self.effectiveAccentColor
				}
				let (r, g, b) = Self.clampedSRGBComponents(from: Self.defaultAccentColor)
				return Self.strictSRGBColor(red: r, green: g, blue: b)
			},
			set: { newValue in
				let (r, g, b) = Self.clampedSRGBComponents(from: newValue)
				self.customAccentColorComponents = "\(r),\(g),\(b)"
				self.objectWillChange.send()
			}
		)
	}
	
	private static func clampedSRGBComponents(from color: Color) -> (Double, Double, Double) {
		let cgColor = UIColor(color).cgColor
		if let srgbSpace = CGColorSpace(name: CGColorSpace.sRGB),
		   let converted = cgColor.converted(to: srgbSpace, intent: .defaultIntent, options: nil),
		   let components = converted.components,
		   components.count >= 3
		{
			return (
				min(max(Double(components[0]), Double(0)), Double(1)),
				min(max(Double(components[1]), Double(0)), Double(1)),
				min(max(Double(components[2]), Double(0)), Double(1))
			)
		}
		var red: CGFloat = 0
		var green: CGFloat = 0
		var blue: CGFloat = 0
		var alpha: CGFloat = 0
		if UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
			return (
				min(max(Double(red), Double(0)), Double(1)),
				min(max(Double(green), Double(0)), Double(1)),
				min(max(Double(blue), Double(0)), Double(1))
			)
		}
		return (Double(1), Double(0), Double(0.311))
	}
	
	private static func strictSRGBColor(red: Double, green: Double, blue: Double) -> Color {
		let r = min(max(red, Double(0)), Double(1))
		let g = min(max(green, Double(0)), Double(1))
		let b = min(max(blue, Double(0)), Double(1))
		if let space = CGColorSpace(name: CGColorSpace.sRGB),
		   let cgColor = CGColor(colorSpace: space, components: [CGFloat(r), CGFloat(g), CGFloat(b), 1])
		{
			return Color(cgColor: cgColor)
		}
		return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
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
