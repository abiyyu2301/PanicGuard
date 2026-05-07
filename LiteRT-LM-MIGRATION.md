# LiteRT-LM + Gemma 4 iOS Integration — Migration Plan

## What We're Building

A Swift wrapper over the LiteRT-LM C++ runtime (`libLiteRt.dylib`) to run **Gemma 4 2B** inference natively on iOS, replacing the deprecated `MediaPipeTasksGenai` stack.

**Why this matters:** MediaPipe LLM Inference is officially deprecated. LiteRT-LM is its successor and natively supports Gemma 4 — but the Swift API is still "In Dev."

---

## Context

- Gemma 4 2B is a **featured model** on LiteRT-LM overview: 2.58 GB, iPhone 17 Pro GPU delivers ~2,878 tk/s prefill, 0.3s time to first token
- Prebuilt iOS dylibs exist at `prebuilt/ios_arm64/` in the [google-ai-edge/LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) repo:
  - `libLiteRt.dylib`
  - `libLiteRtMetalAccelerator.dylib`
  - `libLiteRtTopKMetalSampler.dylib`
  - `libGemmaModelConstraintProvider.dylib`
- Swift API: **"🚀 In Dev — Coming Soon"** (official docs)
- iOS path currently is **C++ only** — no CocoaPods pod, no Swift package
- The Google AI Edge Gallery iOS app is the reference implementation (closed-source)

---

## Step-by-Step Work Items

### 1. Research First (in next session)

Confirm these before writing any code:

**a) Model format**
- LiteRT-LM uses `.litertlm` format (not `.gguf`, not `.bin`)
- Check HuggingFace for pre-converted Gemma 4: `https://huggingface.co/liteRT`
- If not available → need to build the conversion tool from source

**b) CocoaPods / Swift package availability**
- Search GitHub for `LiteRt-LM.podspec` or `litert-lm-swift`
- Prebuilt dylibs may need manual `.xcframework` packaging for Xcode

**c) Exact C API headers**
- Check `c/litert*.h` in the [main repo](https://github.com/google-ai-edge/LiteRT-LM/tree/main/c)
- Confirm function signatures for: model loading, inference, streaming
- These determine what the Swift interop layer looks like

**d) Gallery iOS app source**
- Try: `https://github.com/google-ai-edge/LiteRT-LM/tree/main/examples/ios`
- If not public → build from dylibs + C API docs alone

---

### 2. Set Up iOS Project to Use LiteRT-LM Dylibs

**Download prebuilt binaries:**
```bash
git clone https://github.com/google-ai-edge/LiteRT-LM
# Copy from LiteRT-LM/prebuilt/ios_arm64/:
#   libLiteRt.dylib
#   libLiteRtMetalAccelerator.dylib
#   libLiteRtTopKMetalSampler.dylib
#   libGemmaModelConstraintProvider.dylib
```

**Create an `.xcframework`** or embed dylibs in the Xcode project. Add to `project.yml` under XcodeGen sources.

**Add a Bridging Header** (`PanicGuard-Bridging-Header.h`):
```objc
#include "litert.h"
#include "litert_model.h"
#include "litert_engine.h"
// (exact headers TBD — confirm from repo's c/ directory)
```

---

### 3. Write the Swift-C++ Interop Layer

**New file: `Gemma/LiteRTModel.swift`**
```swift
import Foundation
// imports via bridging header

class LiteRTModel {
    private var model: OpaquePointer?
    private var engine: OpaquePointer?

    init(modelPath: String) throws {
        var model: OpaquePointer?
        let result = litert_model_load_from_file(modelPath, &model)
        guard result == LITERT_OK else { throw LiteRTError.loadFailed(result) }
        self.model = model

        var engine: OpaquePointer?
        let engineResult = litert_engine_create(model, &engine)
        guard engineResult == LITERT_OK else { throw LiteRTError.engineFailed(engineResult) }
        self.engine = engine
    }

    func generateResponse(prompt: String) throws -> String {
        // TBD — depends on C API signatures
    }

    func generateResponseStream(prompt: String) throws -> AsyncStream<String> {
        // TBD — depends on C API signatures
    }
}

enum LiteRTError: Error {
    case loadFailed(Int32)
    case engineFailed(Int32)
    case inferenceFailed(Int32)
}
```

**New file: `Gemma/GemmaServiceLiteRT.swift`**
- Drop-in replacement for `GemmaService.swift`
- Keep the same public interface: `generateResponse(inputText:)`, `generateResponseAsync(inputText:)`
- Internally uses `LiteRTModel` instead of `MediaPipeTasksGenai.LlmInference`
- All existing prompt builders (`GemmaPromptBuilder.swift`, `GemmaDispatch.swift`, etc.) **do not need changes** — they're model-agnostic

---

### 4. Model Download / Conversion

**Option A — Use pre-converted model (fastest):**
```bash
huggingface-cli download liteRT/gemma-4-E2B-it litertlm_model.bin
# or
huggingface-cli download google/gemma-4-2b-it litertlm_model.bin
```

**Option B — Convert GGUF → LiteRT format:**
- Build conversion tool from source (requires Bazel, see `docs/getting-started/cmake.md`)
- ```bash
  bazel run //tools:litert_lm_builder -- \
    --input=gemma-4-E2B-it-Q4_K_M.gguf \
    --output=gemma-4-E2B-it.litertlm \
    --backend=metal
  ```
- Place output `.litertlm` in `Detection/Gemma/` and add to Xcode project bundle

**Recommended quant:** `gemma-4-E2B-it-Q4_K_M.gguf` (3.11 GB) or `gemma-4-E2B-it-UD-Q4_K_XL.gguf` (3.18 GB) from `unsloth/gemma-4-E2B-it-GGUF`

---

### 5. Update Xcode Project Configuration

**`project.yml`** (XcodeGen):
```yaml
targets:
  PanicGuard:
    sources:
      - path: Detection/Gemma
        excludes:
          - "*.gguf"
          - "*.litertlm"
      - path: Detection/Gemma/gemma-4-E2B-it.litertlm
        type: file
    settings:
      SWIFT_OBJC_BRIDGING_HEADER: PanicGuard/PanicGuard-Bridging-Header.h
      OTHER_LDFLAGS:
        - -force_load (path to dylibs)
      LD_RUNPATH_SEARCH_PATHS: $(inherited) @executable_path/Frameworks
```

**`Podfile`:** Remove these lines (no longer needed):
```
pod 'MediaPipeTasksGenAI'
pod 'MediaPipeTasksGenAIC'
```

Then regenerate:
```bash
xcodegen generate && pod install
```

---

### 6. Build & Verify

```bash
xcodebuild \
  -workspace PanicGuard.xcworkspace \
  -scheme PanicGuard \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

On a **real device**: confirm Gemma 4 loads and responds to prompts.

---

## Files to Modify / Create

| File | Status |
|---|---|
| `Gemma/GemmaServiceLiteRT.swift` | **Done** — LiteRT implementation |
| `Gemma/LiteRTModel.swift` | **Done** — Swift-C++ interop wrapper |
| `PanicGuard-Bridging-Header.h` | **Done** — C++ header imports |
| `c/litert_engine.h` | **Done** — LiteRT C API header |
| `project.yml` | **Done** — bridging header + linker flags |
| `Podfile` | **Done** — MediaPipe pods removed |
| `scripts/download-litert-dylibs.sh` | **Done** — dylib download script |
| `scripts/download-gemma-model.sh` | **Done** — model download/convert script |
| `Detection/Gemma/gemma-4-E2B-it.litertlm` | **TODO** — download model |
| `prebuilt/ios_arm64/*.dylib` | **TODO** — run download script |

---

## Remaining Steps (In Order)

### Step 1: Download dylibs
```bash
chmod +x scripts/download-litert-dylibs.sh
./scripts/download-litert-dylibs.sh
```

### Step 2: Download Gemma 4 model
```bash
chmod +x scripts/download-gemma-model.sh
./scripts/download-gemma-model.sh
# Or for a specific GGUF: ./scripts/download-gemma-model.sh --convert /path/to/model.gguf
```

### Step 3: Regenerate Xcode project
```bash
xcodegen generate && pod install
```

### Step 4: Build & verify
```bash
xcodebuild \
  -workspace PanicGuard.xcworkspace \
  -scheme PanicGuard \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

---

## Key Decisions Made

**C API chosen over higher-level wrappers:** The LiteRT Swift API is still "In Dev" per official docs, so we use the C API (`litert_engine.h`) directly with a Swift interop layer.

**Dylibs downloaded manually, not CocoaPods:** No LiteRT-LM CocoaPods pod or Swift Package exists. Prebuilt iOS dylibs are downloaded from GitHub and embedded via `OTHER_LDFLAGS -force_load`.

**Bridging header + C API:** The C API headers are copied into the project (`c/litert_engine.h`) and included via a Swift bridging header. No Swift Package Manager workaround needed.

**Model format:** `.litertlm` (not `.gguf` or `.bin`). Gemma 4 2B ships in this format. Use the download script to get a pre-converted model.

**Session-per-inference pattern:** `LiteRTModel.createSession()` is called before each inference. The session is cached and reused. This matches the MediaPipe `LlmInference` lifecycle.

**Simulation mode preserved:** Both `GemmaService.swift` (MediaPipe) and `GemmaServiceLiteRT.swift` fall back to deterministic simulation when no model is bundled. All prompt builders, dispatch logic, and result parsers are unchanged.
