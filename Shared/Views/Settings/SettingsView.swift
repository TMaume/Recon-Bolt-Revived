import SwiftUI
import ValorantAPI
import WidgetKit

struct SettingsView: View {
	@ObservedObject var accountManager: AccountManager
	@ObservedObject var assetManager: AssetManager
	@ObservedObject var settings: AppSettings
	@ObservedObject var store: InAppStore
	
	@StateObject var iconManager = AppIconManager()
	/// Lives outside the `Form` so re-renders of the list (e.g. on scene activation) can never recreate the login sheet.
	@State private var loginTarget: AccountSettingsView.LoginTarget?
	@StateObject private var loginWebViewModel = RiotLoginWebViewModel()
	
	@Namespace private var storefrontID
	
	var body: some View {
		ScrollViewReader { scrollView in
			Form {
				AccountSettingsView(
					accountManager: accountManager,
					loginTarget: $loginTarget,
					showSignOutButton: false
				)
				
				Section(header: Text("Settings", comment: "Settings: section")) {
					mainSettings()
				}
				
				Section {
					NavigationLink {
						StorageView(accountManager: accountManager, assetManager: assetManager, settings: settings)
					} label: {
						Label {
							Text("Storage and Data")
						} icon: {
							Image(systemName: "arrow.up.arrow.down")
								.foregroundStyle(.tint)
						}
					}
					
					NavigationLink {
						AdvancedSettingsView(accountManager: accountManager, assetManager: assetManager, settings: settings)
					} label: {
						Label {
							Text("Advanced Settings")
						} icon: {
							Image(systemName: "slider.horizontal.3")
								.foregroundStyle(.tint)
						}
					}
				}
				
				Section(header: Text("About", comment: "Settings: section")) {
					NavigationLink {
						AboutScreen()
					} label: {
						Label {
							Text("About Recon Bolt Revived")
						} icon: {
							Image(systemName: "questionmark")
								.foregroundStyle(.tint)
						}
					}
					
					ListLink("DT-L21", icon: "person", destination: "https://guns.lol/dt.l21")
				}
				.id(storefrontID)
			}
			.deepLinkHandler { deepLink in
				guard case .inApp(.storefront) = deepLink else { return }
				withAnimation {
					scrollView.scrollTo(storefrontID, anchor: .center)
				}
			}
		}
		.sheet(item: $loginTarget) { _ in
			LoginForm(accountManager: accountManager, webViewModel: loginWebViewModel)
				.withLoadErrorAlerts()
		}
		.onChange(of: loginTarget) { target in
			// fresh Riot login page only when a new sign-in starts, never on app/scene re-activation
			if target != nil {
				loginWebViewModel.startNewSession(clearWebData: settings.clearWebSignInDataOnOpen)
			}
		}
		.navigationTitle("Settings")
	}
	
	@ViewBuilder
	func mainSettings() -> some View {
		Picker(selection: $settings.theme) {
			ForEach(AppSettings.Theme.allCases, id: \.self) { theme in
				theme.name
					.tag(theme)
			}
		} label: {
			Label {
				Text("Theme", comment: "Settings: picker")
			} icon: {
				Image(systemName: "sun.max")
					.foregroundStyle(.tint)
			}
		}
		
		NavigationLink {
			AppIconPicker(manager: iconManager)
		} label: {
			Label {
				HStack {
					Text("App Icon", comment: "Settings: button")
					Spacer()
					iconManager.currentIcon.name
						.foregroundStyle(.secondary)
				}
			} icon: {
				Image(systemName: "square.dashed")
					.foregroundStyle(.tint)
			}
		}
		
		ColorPicker(selection: settings.accentColorBinding, supportsOpacity: false) {
			Label {
				Text("Custom Accent Color")
			} icon: {
				Image(systemName: "paintpalette")
					.foregroundStyle(.tint)
			}
		}
		
		Button {
			settings.resetAccentColor()
		} label: {
			Label {
				HStack {
					Text("Reset to Default Color")
						.foregroundStyle(settings.hasCustomAccentColor ? Color.accentColor : Color.secondary)
					Spacer()
					if !settings.hasCustomAccentColor {
						Text("Default")
							.foregroundStyle(.secondary)
					}
				}
			} icon: {
				Image(systemName: "arrow.counterclockwise")
					.foregroundStyle(settings.hasCustomAccentColor ? Color.accentColor : Color.secondary)
			}
		}
		.disabled(!settings.hasCustomAccentColor)
	}
}

private extension AppSettings.Theme {
	var name: Text {
		switch self {
		case .system:
			return Text("Match System", comment: "App Theme: automatically match the system theme")
		case .light:
			return Text("Light Mode", comment: "App Theme")
		case .dark:
			return Text("Dark Mode", comment: "App Theme")
		}
	}
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
	static var previews: some View {
		SettingsView(accountManager: .mocked, assetManager: .forPreviews, settings: .init(), store: .init())
			.withToolbar()
		
		AdvancedSettingsView(accountManager: .mocked, assetManager: .forPreviews, settings: .init())
			.withToolbar()
			.previewDisplayName("Advanced Settings")
		
		SettingsView(accountManager: .mockEmpty, assetManager: .mockEmpty, settings: .init(), store: .init())
			.withToolbar()
			.previewDisplayName("Empty Managers")
		
		AppIconPicker(manager: .init())
			.withToolbar()
			.previewDisplayName("App Icon Picker")
	}
}
#endif
