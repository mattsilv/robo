---
title: "fix: Registration fails with RoboAPI error 2 on re-register"
type: fix
status: completed
date: 2026-02-14
issue: "#142"
---

# fix: Registration fails with RoboAPI error 2 on re-register

## Overview

When tapping "Re-register Device" in Settings, registration fails with a cryptic "RoboAPI error 2" message. PR #140 fixed the **client-side rollback** (old config preserved on failure), but the **root cause of the registration failure itself** is unresolved.

## Root Cause Analysis

### What "RoboAPI error 2" actually means

There is **no "RoboAPI" error code** on the server. "Error 2" is Swift's auto-generated `NSError` representation of `APIError.invalidResponse` (the 3rd enum case, 0-indexed):

```swift
// ios/Robo/Services/APIService.swift:3-9
enum APIError: Error {
    case invalidURL          // error 0
    case requestFailed(Error) // error 1
    case invalidResponse     // error 2  ← THIS ONE
    case decodingError(Error) // error 3
    case httpError(statusCode: Int, message: String) // error 4
}
```

The user sees: `"Registration failed: The operation couldn't be completed. (Robo.APIError error 2.)"`

### Server is working fine

Tested `POST https://api.robo.app/api/devices/register` from CLI — returns `201` with valid JSON including `mcp_token`. No auth middleware on this endpoint. Fresh UUID generated each time, no constraint violations possible.

### The `invalidResponse` error is thrown only here:

```swift
// ios/Robo/Services/APIService.swift:105-107
guard let httpResponse = response as? HTTPURLResponse else {
    throw APIError.invalidResponse  // ← The ONLY place error 2 is thrown
}
```

This cast fails when `URLSession.data(for:)` returns a non-HTTP response — which should never happen for a real HTTPS request to `api.robo.app`.

### Most likely causes

1. **Cloudflare challenge/block page** — Cloudflare may serve a challenge (HTML) that triggers a redirect to a non-HTTP response, or the Workers deployment was temporarily down when the user tested
2. **Network interception** — captive portal, VPN, or proxy returning non-HTTP response
3. **Transient Workers error** — D1 cold start, deployment in progress, or Workers runtime error returning malformed response
4. **Actually a different error** — The issue author may be paraphrasing; the real error could be `decodingError` (error 3) or `requestFailed` (error 1) but the message was unclear

### Why we can't diagnose further without code changes

The current error handling discards all context. When `invalidResponse` fires, we lose:
- The raw response body
- HTTP status code (if any)
- Response headers
- The underlying error type

## Proposed Solution

Two-part fix: **improve diagnostics** so we can identify the actual failure, and **improve error messages** so users see actionable text instead of "error 2".

### Part 1: Add diagnostic error context

**File:** `ios/Robo/Services/APIService.swift`

1. Make `APIError` conform to `LocalizedError` with human-readable descriptions
2. Add response body context to error cases where possible
3. Log raw response details on failure (debug builds only)

```swift
enum APIError: Error, LocalizedError {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse
    case decodingError(Error)
    case httpError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL. Check your API settings."
        case .requestFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "Unexpected server response. Please try again."
        case .decodingError:
            return "Could not read server response. The app may need updating."
        case .httpError(let code, let message):
            return "Server error (\(code)): \(message)"
        }
    }
}
```

4. In `performRequest`, add logging before throwing:

```swift
private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
    do {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            #if DEBUG
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            print("[APIService] invalidResponse — URL: \(request.url?.absoluteString ?? "nil"), body preview: \(String(body.prefix(200)))")
            #endif
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            #if DEBUG
            print("[APIService] httpError — \(httpResponse.statusCode) for \(request.url?.absoluteString ?? "nil"): \(String(message.prefix(200)))")
            #endif
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        return try JSONDecoder().decode(T.self, from: data)
    } catch let error as DecodingError {
        #if DEBUG
        print("[APIService] decodingError — \(error)")
        #endif
        throw APIError.decodingError(error)
    } catch let error as APIError {
        throw error
    } catch {
        #if DEBUG
        print("[APIService] requestFailed — \(error)")
        #endif
        throw APIError.requestFailed(error)
    }
}
```

### Part 2: Better error display in Settings

**File:** `ios/Robo/Views/SettingsView.swift` (or wherever re-register UI lives)

The `registrationError` string already shows in Settings (added in PR #140). With `LocalizedError` conformance, `lastError?.localizedDescription` will now produce human-readable text instead of "error 2".

No UI changes needed — the existing error display will automatically show better messages.

### Part 3: Add health check before re-register (optional, low effort)

**File:** `ios/Robo/Services/APIService.swift`

Add a quick `/health` check before attempting re-register to catch obvious connectivity issues early:

```swift
func checkHealth() async -> Bool {
    guard let url = try? makeURL(path: "/health") else { return false }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 5
    guard let (_, response) = try? await URLSession.shared.data(for: request),
          let http = response as? HTTPURLResponse,
          http.statusCode == 200 else { return false }
    return true
}
```

**File:** `ios/Robo/Services/DeviceService.swift`

Call health check in `reRegister()` before wiping config:

```swift
func reRegister(apiService: DeviceRegistering) async {
    // Quick connectivity check (if APIService)
    if let api = apiService as? APIService, !(await api.checkHealth()) {
        self.registrationError = "Cannot reach server. Check your internet connection."
        return
    }
    // ... existing re-register logic
}
```

## Acceptance Criteria

- [x] `APIError` conforms to `LocalizedError` with user-friendly messages
- [x] Debug builds log raw response details on API failures
- [x] Re-register error shows readable message (not "error 2")
- [x] Health check prevents re-register when server is unreachable
- [x] Existing tests still pass (if any)
- [ ] Test re-register on physical device

## Files to Change

| File | Change |
|------|--------|
| `ios/Robo/Services/APIService.swift` | `LocalizedError` conformance, debug logging, health check |
| `ios/Robo/Services/DeviceService.swift` | Health check before re-register |

## Risk Assessment

- **Low risk** — Changes are additive (logging, error messages), no behavioral changes to the happy path
- **PR #140 rollback logic unchanged** — Old config still preserved on failure
- **Debug logging only** — No sensitive data logged in production builds

## References

- Issue: #142
- PR #140 (client-side rollback fix): `fe26fd9`
- `ios/Robo/Services/APIService.swift:101-124` (performRequest)
- `ios/Robo/Services/DeviceService.swift:69-85` (reRegister)
- `workers/src/routes/devices.ts:4-36` (server registration endpoint)
