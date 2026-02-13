---
title: "Export filename sanitization — path traversal and control character prevention"
category: security
date: 2026-02-13
component: ios-export
tags: [export, filename, sanitization, path-traversal, security, zip, control-characters]
severity: high
symptoms:
  - "User-supplied room names used directly in file paths"
  - "Potential path traversal via ../../../ in room names"
  - "Control characters (tabs, newlines) in filenames cause filesystem issues"
related_prs: [105]
---

# Export Filename Sanitization — Path Traversal and Control Character Prevention

## Problem

`ExportService.swift` used user-supplied room names directly in file and directory paths when creating export ZIPs. A room named `../../etc/passwd` or containing control characters could create files outside the intended export directory or cause filesystem issues.

## Symptoms

- Room names flowed unsanitized into `appendingPathComponent()` calls
- No protection against path traversal sequences (`../`)
- No protection against filesystem-hostile characters (`/`, `\`, `:`, `*`, etc.)
- No protection against control characters (NUL, tabs, newlines, DEL)

## Root Cause

The original export code used room names directly:

```swift
// ExportService.swift — BEFORE
let zipName = "robo-\(roomName)-\(dateFormatter.string(from: Date())).zip"
let roomDir = roomsDir.appendingPathComponent(roomName)
```

No sanitization was applied. While iOS sandboxing limits the blast radius, this is still a defense-in-depth failure.

## Solution

Added `sanitizeFilename()` to `ExportService.swift` and applied it at all callsites where user-supplied names enter file paths.

```swift
static func sanitizeFilename(_ name: String) -> String {
    // Strip control characters (NUL, tabs, newlines, DEL, etc.)
    var safe = String(name.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F })
    safe = safe
        .replacingOccurrences(of: " ", with: "-")
        .lowercased()
    // Strip filesystem-hostile characters
    safe = safe.replacingOccurrences(of: "/", with: "-")
    safe = safe.replacingOccurrences(of: "\\", with: "-")
    safe = safe.replacingOccurrences(of: ":", with: "-")
    safe = safe.replacingOccurrences(of: "*", with: "")
    safe = safe.replacingOccurrences(of: "?", with: "")
    safe = safe.replacingOccurrences(of: "\"", with: "")
    safe = safe.replacingOccurrences(of: "<", with: "")
    safe = safe.replacingOccurrences(of: ">", with: "")
    safe = safe.replacingOccurrences(of: "|", with: "")
    // Prevent hidden files and collapse repeated dashes
    while safe.hasPrefix(".") { safe = String(safe.dropFirst()) }
    while safe.contains("--") {
        safe = safe.replacingOccurrences(of: "--", with: "-")
    }
    // Length limit
    if safe.count > 60 { safe = String(safe.prefix(60)) }
    // Fallback if nothing remains
    if safe.trimmingCharacters(in: .punctuationCharacters).isEmpty { safe = "room" }
    return safe
}
```

### Callsites patched

1. **Single room export** (`createRoomExportZipFromData`): ZIP filename
2. **Combined export** (`createCombinedExportZip`): Room subdirectory names

### Dedup suffix overflow fix

The combined export deduplicates room directory names by appending `-2`, `-3`, etc. The suffix is now accounted for in the 60-char limit:

```swift
// BEFORE — could exceed 60 chars
safeName = "\(baseName)-\(counter)"

// AFTER — truncates base to fit suffix within limit
let suffix = "-\(counter)"
let maxBase = 60 - suffix.count
safeName = "\(String(baseName.prefix(maxBase)))\(suffix)"
```

### XML escaping hardened

`FloorPlanSVGGenerator.escapeXML()` was also updated to escape `'` and `"` (single/double quotes) in addition to `&`, `<`, `>`, since room names appear in SVG text elements.

## Prevention Pattern

**Always sanitize user input before using in filesystem paths.** Even in sandboxed iOS apps:

1. Strip control characters via unicode scalar filtering
2. Replace path separators (`/`, `\`) with safe alternatives
3. Remove filesystem-hostile characters
4. Enforce a length limit
5. Provide a fallback for empty results
6. When appending suffixes for dedup, account for the suffix in the length limit

## Related

- `ExportService.swift:506-527` — `sanitizeFilename()` implementation
- `ExportService.swift:383-389` — dedup suffix with length cap
- `FloorPlanSVGGenerator.swift:109-116` — hardened XML escaping
- PR #105
