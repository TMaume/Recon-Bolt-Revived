import Foundation

enum LocalJSONStore {
	private struct UncheckedBox<T>: @unchecked Sendable {
		let value: T
	}
	
	private static let ioQueue = DispatchQueue(label: "com.reconbolt.localjsonstore", qos: .utility)
	
	private static func makeDecoder() -> JSONDecoder {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return decoder
	}
	
	private static func makeEncoder() -> JSONEncoder {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		return encoder
	}
	
	static func url(for filename: String) -> URL {
		FolderLocations.localData.appendingPathComponent(filename, isDirectory: false)
	}
	
	static func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
		let fileURL = url(for: filename)
		return ioQueue.sync {
			decodeOnQueue(T.self, from: fileURL)
		}
	}
	
	static func loadAsync<T: Decodable>(_ type: T.Type, from filename: String) async -> T? {
		let fileURL = url(for: filename)
		let box = await withCheckedContinuation { (continuation: CheckedContinuation<UncheckedBox<T?>, Never>) in
			ioQueue.async {
				let decoded = decodeOnQueue(T.self, from: fileURL)
				continuation.resume(returning: UncheckedBox(value: decoded))
			}
		}
		return box.value
	}
	
	static func save<T: Encodable>(_ value: T, to filename: String) {
		let fileURL = url(for: filename)
		let boxed = UncheckedBox(value: value)
		ioQueue.async {
			do {
				try FileManager.default.createDirectory(
					at: fileURL.deletingLastPathComponent(),
					withIntermediateDirectories: true
				)
				let data = try makeEncoder().encode(boxed.value)
				try data.write(to: fileURL, options: .atomic)
			} catch {
				print("Failed saving \(filename):", error)
			}
		}
	}
	
	private static func decodeOnQueue<T: Decodable>(_ type: T.Type, from fileURL: URL) -> T? {
		guard let data = try? Data(contentsOf: fileURL) else { return nil }
		return try? makeDecoder().decode(T.self, from: data)
	}
}
