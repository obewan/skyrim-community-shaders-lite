# New Feature Development Reference

Quick reference for creating new graphics features in Community Shaders.

## File Structure

Template files to copy and customize:

-   `docs/new-feature-template/NewFeature.h` → Copy to `src/Features/YourFeature.h`
-   `docs/new-feature-template/NewFeature.cpp` → Copy to `src/Features/YourFeature.cpp`
-   `docs/new-feature-template/New Feature/` → Copy to `features/YourFeature/`

## Core System Registration

These are the **required** files that must be modified for your feature to appear in settings:

### 1. `src/Globals.h`

**Forward Declaration** - Add at top with other feature declarations:

struct YourFeature;

**Feature Instance Declaration** - Add in `globals::features` namespace:

extern YourFeature yourFeature;

### 2. `src/Globals.cpp`

**Feature Instance Definition** - Add in `globals::features` namespace:

YourFeature yourFeature{};

### 3. `src/Feature.cpp`

**Feature Registration** - Add to features vector in `GetFeatureList()`:

&globals::features::yourFeature,

## Template Customization

### Class Names

-   Replace all `NewFeature` → `YourFeature`
-   Replace all `"New Feature"` → `"Your Feature Name"`
-   Replace all `"NewFeature"` → `"YourFeature"`

### Metadata

-   `GetCategory()` → Choose: "Lighting", "Effects", "Rendering", "Performance", "Terrain", "Water", "Atmosphere"
-   `GetFeatureModLink()` → Update Nexus mod ID
-   `GetFeatureSummary()` → Update description and features list
-   `GetShaderDefineName()` → Your preprocessor define name
-   `HasShaderDefine()` → Which shader types use your define

### Settings

-   Update `Settings` struct with your parameters
-   Update `CbData` struct for shader constant buffer (must be 16-byte aligned); per-frame settings shared with game shaders go in the spare slots (below)
-   Update NLOHMANN serialization macro
-   Customize `DrawSettings()` UI controls
-   Update shader compilation paths in `CompileShaders()`

## Spare settings slots

Every shader includes `package/Shaders/Common/SharedData.hlsli`, so adding a settings struct to its
`FeatureData` cbuffer changes every permutation and costs a full shader recompile. New features put
their per-frame settings in the reserved `SharedData::SpareSlots` block instead, so adding or
changing a setting only recompiles the shaders that include the feature's own `.hlsli`.

1. Pick a free slot range. The claims are listed in `spareClaims` in `src/FeatureBuffer.cpp`; a
   `static_assert` rejects overlaps and overflow. The block holds `FeatureSpareSlots::Count` (32)
   float4 slots.
2. In `src/Features/YourFeature.h`, declare the first slot and a 16-byte-padded settings struct:

    ```cpp
    static constexpr uint32_t SpareSlot = 0;
    struct alignas(16) Settings
    {
    	uint Enabled = 1;
    	float Brightness = 1.0f;
    	float2 pad0;
    };
    ```

3. In `src/FeatureBuffer.cpp`, add the claim and the write:

    ```cpp
    constexpr std::array<FeatureSpareSlots::Claim, 1> spareClaims{ {
    	{ "YourFeature", YourFeature::SpareSlot, FeatureSpareSlots::SlotsFor<YourFeature::Settings>() },
    } };
    // in GetSpareSlotData():
    FeatureSpareSlots::Write(block, YourFeature::SpareSlot, globals::features::yourFeature.settings);
    ```

4. In the feature's `.hlsli`, unpack the slots. Integers and bools arrive as raw bits, so read them
   with `asuint`:

    ```hlsl
    namespace YourFeature
    {
    	static const uint SpareSlot = 0;  // YourFeature::SpareSlot in src/Features/YourFeature.h

    	struct Settings
    	{
    		uint Enabled;
    		float Brightness;
    	};

    	Settings GetSettings()
    	{
    		const float4 s0 = SharedData::SpareSlots[SpareSlot];
    		Settings s;
    		s.Enabled = asuint(s0.x);
    		s.Brightness = s0.y;
    		return s;
    	}
    }
    ```

Do not edit `SharedData.hlsli` for the feature. Once several features in the spare slots have
settled, they can be moved into proper `FeatureData` structs together, at the cost of one full recompile.

## Naming Conventions

| Component          | Convention | Example                 |
| ------------------ | ---------- | ----------------------- |
| C++ Class          | PascalCase | `YourFeature`           |
| Instance Variable  | camelCase  | `yourFeature`           |
| Display Name       | Spaces     | `"Your Feature Name"`   |
| Short Name         | PascalCase | `"YourFeature"`         |
| Features Directory | PascalCase | `features/YourFeature/` |
| Shader Directory   | PascalCase | `YourFeature/`          |

## Automatic Build Integration

The build system automatically handles:

-   Shader compilation and validation
-   Settings persistence (JSON serialization)
-   UI menu integration
-   Feature lifecycle management
-   Cross-platform builds (SE/AE)

Build with: `./BuildRelease.bat ALL`

## Testing Checklist

-   [ ] Feature appears in settings menu
-   [ ] Settings save/load correctly
-   [ ] Shaders compile without errors
-   [ ] Feature works in-game
-   [ ] No build errors
