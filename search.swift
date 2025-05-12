#!/usr/bin/env swift

import Foundation

// MARK: - Error Types

enum TenorAPIError: Error {
  case httpError(statusCode: Int)
  case decodingError(Error)
}

enum CacheError: Error {
  case httpError
  case invalidGIF
  case fileSystemError(Error)
}

// MARK: - Configuration

struct Config {
  let apiKey: String
  let tenorAPIURL: URL
  let limit: Int
  let previewQuality: String
  let outputQuality: String
  let cacheEnabled: Bool
  let cacheDirectory: URL
  let fallbackIcon: URL

  static func fromEnvironment() -> Config {
    let env = ProcessInfo.processInfo.environment
    let apiKey = env["API_KEY"].unsafelyUnwrapped  // We can unwrap here because when this is run with alfred, this is a required field.
    let baseURL = URL(string: "https://tenor.googleapis.com/v2/")!
    let limit = Int(env["MAX_RESULTS"] ?? "") ?? 5
    let previewQuality = env["PREVIEW_QUALITY"] ?? "nanogif"
    let outputQuality = env["OUTPUT_QUALITY"] ?? "tinygif"
    let cacheEnabled =
      (env["CACHE_ENABLED"] ?? "true")
      .lowercased() == "true"

    // Using built-in alfred directories for handling
    let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
    let workflowDir = scriptURL.deletingLastPathComponent()
    let cacheDirName = env["CACHE_DIR_NAME"] ?? "cache"
    let cacheDir =
      workflowDir
      .appendingPathComponent(cacheDirName, isDirectory: true)
    let fallbackIconPath = env["FALLBACK_ICON"] ?? "./icon.png"
    let fallbackIcon = URL(
      fileURLWithPath: fallbackIconPath,
      relativeTo: workflowDir
    )
    .standardizedFileURL

    return Config(
      apiKey: apiKey,
      tenorAPIURL: baseURL,
      limit: limit,
      previewQuality: previewQuality,
      outputQuality: outputQuality,
      cacheEnabled: cacheEnabled,
      cacheDirectory: cacheDir,
      fallbackIcon: fallbackIcon)
  }
}

// MARK: - Cache Manager

actor CacheManager {
  let cacheDirectory: URL

  init(config: Config) throws {
    self.cacheDirectory = config.cacheDirectory
    try FileManager.default
      .createDirectory(
        at: cacheDirectory,
        withIntermediateDirectories: true,
        attributes: nil)
  }

  // We're treating the names that the gifs are named as more or less random. There can be overlap, but it's very rare, and the cache gets reset frequently anyways. A real solution would involve hasing the contents, but that seems a little excessive right now.
  func cachedFilePath(for url: URL) -> URL {
    cacheDirectory.appendingPathComponent(url.lastPathComponent)
  }

  // This could be done on the Alfred side as well, but they have a hard cap of a day or two.
  func cacheGIFIfNotExists(from url: URL) async throws -> URL {
    let fileURL = cachedFilePath(for: url)
    if FileManager.default.fileExists(atPath: fileURL.path) {
      return fileURL
    }
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let httpResp = response as? HTTPURLResponse,
      httpResp.statusCode == 200
    else {
      throw CacheError.httpError
    }
    guard data.count >= 6,
      let header = String(data: data.prefix(6), encoding: .ascii),
      header.hasPrefix("GIF")
    else {
      throw CacheError.invalidGIF
    }
    let tempURL = fileURL.appendingPathExtension("tmp")
    do {
      try data.write(to: tempURL)
      try FileManager.default.moveItem(at: tempURL, to: fileURL)
      return fileURL
    } catch {
      try? FileManager.default.removeItem(at: tempURL)
      throw CacheError.fileSystemError(error)
    }
  }
}

// MARK: - Tenor API Models

struct TenorSearchResponse: Codable {
  let results: [TenorResult]
}

struct TenorResult: Codable {
  let id: String
  let contentDescription: String?
  let itemURL: URL?
  let mediaFormats: [String: MediaFormat]

  enum CodingKeys: String, CodingKey {
    case id
    case contentDescription = "content_description"
    case itemURL = "itemurl"
    case mediaFormats = "media_formats"
  }
}

struct MediaFormat: Codable {
  let url: URL
}

// MARK: - Alfred JSON Models

// There exists a Swift library for handling this, but I didn't know if you could pull in external libs while running as a script, so I just rewrote this.
struct AlfredItem: Codable {
  let uid: String?
  let title: String
  let subtitle: String?
  let arg: String?
  let autocomplete: String?
  let icon: Icon?
  let quicklookurl: String?
  let valid: Bool
  let mods: Mods?

  struct Icon: Codable {
    let path: String
  }
  struct Mods: Codable {
    let alt: ModAction
    let cmd: ModAction

    struct ModAction: Codable {
      let valid: Bool
      let arg: String
      let subtitle: String
    }
  }

  enum CodingKeys: String, CodingKey {
    case uid, title, subtitle, arg, autocomplete, icon,
      quicklookurl, valid, mods
  }
}

struct AlfredOutput: Codable {
  let items: [AlfredItem]
}

// MARK: - Tenor API Call

func fetchTenorResults(
  query: String,
  config: Config
) async throws -> [TenorResult] {
  var components = URLComponents(
    url: config.tenorAPIURL.appendingPathComponent("search"),
    resolvingAgainstBaseURL: false
  )!
  components.queryItems = [
    URLQueryItem(name: "q", value: query),
    URLQueryItem(name: "key", value: config.apiKey),
    URLQueryItem(name: "limit", value: "\(config.limit)"),
    URLQueryItem(
      name: "media_filter",
      value: "\(config.previewQuality),\(config.outputQuality)"),
  ]
  let url = components.url!
  let (data, response) = try await URLSession.shared.data(from: url)
  guard let httpResp = response as? HTTPURLResponse,
    httpResp.statusCode == 200
  else {
    throw TenorAPIError.httpError(
      statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1
    )
  }
  do {
    let decoder = JSONDecoder()
    let resp = try decoder.decode(TenorSearchResponse.self, from: data)
    return resp.results
  } catch {
    throw TenorAPIError.decodingError(error)
  }
}

// MARK: - Concurrent Alfred Item Creation

private struct IndexedItem {
  let index: Int
  let item: AlfredItem
}

func createAlfredItems(
  from results: [TenorResult],
  config: Config,
  cacheManager: CacheManager
) async
  -> [AlfredItem]
{
  // We're using concurrency here even though it's overkill, I'm still expirmenting with how Swift's models work in practice
  await withTaskGroup(of: IndexedItem.self) { group in
    for (idx, result) in results.enumerated() {
      group.addTask {
        // Default icon
        var iconPath = config.fallbackIcon.path
        let previewURL = result.mediaFormats[
          config.previewQuality
        ]?.url
        // Attempt caching
        if config.cacheEnabled, let pURL = previewURL {
          do {
            let cached = try await cacheManager.cacheGIFIfNotExists(from: pURL)
            iconPath = cached.path
          } catch {
            let msg = "Warning: Failed to cache icon for " + "\(result.id): \(error)\n"
            FileHandle.standardError.write(Data(msg.utf8))
          }
        } else if previewURL == nil {
          let msg =
            "Warning: No '\(config.previewQuality)' URL " + "for \(result.id), using fallback.\n"
          FileHandle.standardError.write(Data(msg.utf8))
        }

        // Build URLs
        let outputStr = result.mediaFormats[
          config.outputQuality
        ]?.url.absoluteString
        let previewStr = previewURL?.absoluteString
        let argStr =
          outputStr
          ?? result.itemURL?.absoluteString
          ?? previewStr
          ?? "https://tenor.com/view/\(result.id)"

        // Build item
        let title =
          result.contentDescription
          ?? "GIF Result \(result.id)"
        let subtitle = "Select to copy URL: " + (outputStr != nil ? config.outputQuality : "post")
        let alt = AlfredItem.Mods.ModAction(
          valid: true,
          arg: previewStr ?? argStr,
          subtitle: "Copy \(config.previewQuality) URL: " + "\(previewStr ?? "N/A")"
        )
        let cmd = AlfredItem.Mods.ModAction(
          valid: true,
          arg: result.itemURL?.absoluteString
            ?? "https://tenor.com/view/\(result.id)",
          subtitle: "Open Tenor page: " + "\(result.itemURL?.absoluteString ?? "N/A")"
        )
        let mods = AlfredItem.Mods(alt: alt, cmd: cmd)

        let item = AlfredItem(
          uid: result.id,
          title: title,
          subtitle: subtitle,
          arg: argStr,
          autocomplete: title,
          icon: AlfredItem.Icon(path: iconPath),
          quicklookurl: previewStr ?? argStr,
          valid: true,
          mods: mods
        )
        return IndexedItem(index: idx, item: item)
      }
    }

    // Capturing results
    var buffer: [IndexedItem] = []
    for await it in group {
      buffer.append(it)
    }

    // Preserve original order (Trust Tenor's ranking)
    return buffer.sorted { $0.index < $1.index }
      .map { $0.item }
  }
}

// MARK: - CLI Entry Point

struct GIFSearch {
  static func main() async {
    let args = CommandLine.arguments
    guard args.count > 1 else {
      printUsage()
      return
    }
    let query = args.dropFirst().joined(separator: " ")
    let config = Config.fromEnvironment()

    let cacheManager: CacheManager
    do {
      cacheManager = try CacheManager(config: config)
    } catch {
      printError(
        title: "Cache Init Error",
        subtitle: "\(error)")
      return
    }

    let items: [AlfredItem]
    do {
      let results = try await fetchTenorResults(
        query: query,
        config: config)
      if results.isEmpty {
        items = [
          AlfredItem(
            uid: nil,
            title: "No GIFs found for '\(query)'",
            subtitle: "Try a different search term.",
            arg: nil,
            autocomplete: nil,
            icon: nil,
            quicklookurl: nil,
            valid: false,
            mods: nil
          )
        ]
      } else {
        items = await createAlfredItems(
          from: results,
          config: config,
          cacheManager: cacheManager
        )
      }
    } catch {
      printError(
        title: "Error fetching GIFs",
        subtitle: "\(error)")
      return
    }

    let output = AlfredOutput(items: items)
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .prettyPrinted
      let data = try encoder.encode(output)
      if let s = String(data: data, encoding: .utf8) {
        print(s)
      }
    } catch {
      printError(
        title: "Serialization Error",
        subtitle: "\(error)")
    }
  }

  // REALLY wish I could use swift arg parser, but..
  static func printUsage() {
    let item = AlfredItem(
      uid: nil,
      title: "Usage: swift script.swift <search term>",
      subtitle: "Please provide a search term for GIFs.",
      arg: nil,
      autocomplete: nil,
      icon: nil,
      quicklookurl: nil,
      valid: false,
      mods: nil
    )
    let out = AlfredOutput(items: [item])
    let enc = JSONEncoder()
    enc.outputFormatting = .prettyPrinted
    if let data = try? enc.encode(out),
      let s = String(data: data, encoding: .utf8)
    {
      print(s)
    }
  }

  static func printError(title: String, subtitle: String) {
    let item = AlfredItem(
      uid: nil,
      title: title,
      subtitle: subtitle,
      arg: nil,
      autocomplete: nil,
      icon: nil,
      quicklookurl: nil,
      valid: false,
      mods: nil
    )
    let out = AlfredOutput(items: [item])
    let enc = JSONEncoder()
    enc.outputFormatting = .prettyPrinted
    if let data = try? enc.encode(out),
      let s = String(data: data, encoding: .utf8)
    {
      print(s)
    }
  }
}

await GIFSearch.main()
