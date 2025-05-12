#!/usr/bin/env swift

import Darwin
import Foundation

// MARK: - Models

struct Query {
  let value: String
}

struct APIKey {
  let value: String

  static func fromEnvironment() throws -> APIKey {
    let env = ProcessInfo.processInfo.environment
    if let key = env["API_KEY"],
      !key.isEmpty,
      key != "PLACEHOLDER_API_KEY"
    {
      return APIKey(value: key)
    }
    throw AutocompleteError.missingAPIKey
  }
}

enum AutocompleteError: Error, LocalizedError {
  case missingAPIKey
  case invalidURL
  case requestFailed(underlying: Error)
  case invalidResponse(statusCode: Int)
  case noData
  case decodingFailed(underlying: Error)

  var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      return "No valid API key found. Set the API_KEY environment variable."
    case .invalidURL:
      return "Failed to construct request URL."
    case .requestFailed(let underlying):
      return "Request failed: \(underlying.localizedDescription)"
    case .invalidResponse(let code):
      return "Invalid response (status code \(code))."
    case .noData:
      return "No data received from server."
    case .decodingFailed(let underlying):
      return "Failed to decode response: \(underlying.localizedDescription)"
    }
  }
}

struct AutocompleteResponse: Codable {
  let results: [String]
}

struct AlfredItem: Codable {
  let title: String
  let arg: String
  let valid: Bool
}

struct Cache: Codable {
  let seconds: Int
}

struct AlfredOutput: Codable {
  let cache: Cache
  let items: [AlfredItem]

  static func from(
    response: AutocompleteResponse,
    query: Query
  ) -> AlfredOutput {
    var items = [AlfredItem]()
    items.append(
      AlfredItem(
        title: query.value,
        arg: query.value,
        valid: true)
    )
    for suggestion in response.results where suggestion != query.value {
      items.append(
        AlfredItem(
          title: suggestion,
          arg: suggestion,
          valid: true)
      )
    }
    return AlfredOutput(
      cache: Cache(seconds: 3600),
      items: items)
  }
}

// MARK: - Networking

struct AutocompleteClient {
  private let session: URLSession
  private let apiKey: APIKey

  init(session: URLSession = .shared, apiKey: APIKey) {
    self.session = session
    self.apiKey = apiKey
  }

  func fetchSuggestions(
    for query: Query
  ) async throws -> AutocompleteResponse {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "tenor.googleapis.com"
    components.path = "/v2/autocomplete"
    components.queryItems = [
      URLQueryItem(name: "key", value: apiKey.value),
      URLQueryItem(name: "q", value: query.value),
    ]
    guard let url = components.url else {
      throw AutocompleteError.invalidURL
    }

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(from: url)
    } catch {
      throw AutocompleteError.requestFailed(underlying: error)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw AutocompleteError.invalidResponse(statusCode: -1)
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw AutocompleteError.invalidResponse(
        statusCode: httpResponse.statusCode
      )
    }

    do {
      let decoder = JSONDecoder()
      return try decoder.decode(
        AutocompleteResponse.self,
        from: data
      )
    } catch {
      throw AutocompleteError.decodingFailed(underlying: error)
    }
  }
}

// MARK: - Entry Point

struct AutocompleteScript {
  static func main() async {
    do {
      let args = CommandLine.arguments.dropFirst()
      guard !args.isEmpty else {
        let toolName = URL(
          fileURLWithPath: CommandLine.arguments[0]
        ).lastPathComponent
        print("Usage: \(toolName) <search term>")
        exit(EXIT_FAILURE)
      }

      let queryString = args.joined(separator: " ").lowercased()
      let query = Query(value: queryString)
      let apiKey = try APIKey.fromEnvironment()
      let client = AutocompleteClient(apiKey: apiKey)
      let response = try await client.fetchSuggestions(
        for: query
      )
      let output = AlfredOutput.from(
        response: response,
        query: query
      )

      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      let data = try encoder.encode(output)
      guard
        let jsonString =
          String(data: data, encoding: .utf8)
      else {
        throw AutocompleteError.noData
      }
      print(jsonString)

    } catch {
      let message = "Error: \(error.localizedDescription)\n"
      if let data = message.data(using: .utf8) {
        FileHandle.standardError.write(data)
      }
      exit(EXIT_FAILURE)
    }
  }
}

await AutocompleteScript.main()
