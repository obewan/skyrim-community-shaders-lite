#include "TrueMountains.h"

#include "I18n/I18n.h"
#include "State.h"
#include "Utils/UI.h"

NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_WITH_DEFAULT(
	TrueMountains::Settings,
	Enabled,
	ReliefShadows,
	ReliefDepth,
	Cavity,
	Contrast,
	ColorVariation,
	DebugView)

namespace
{
	/// Lower-case, forward slashes, without the leading data/ and textures/ folders.
	std::string CanonicaliseTexturePath(std::string_view a_path)
	{
		std::string canonical(a_path);
		for (auto& character : canonical)
			character = character == '\\' ? '/' : static_cast<char>(std::tolower(static_cast<unsigned char>(character)));
		if (canonical.starts_with("data/"))
			canonical.erase(0, 5);
		if (canonical.starts_with("textures/"))
			canonical.erase(0, 9);
		return canonical;
	}

	/// Rock textures live under landscape/ (also prefixed copies such as pbr/landscape/): vanilla
	/// mountains/ and rocks/ folders, plus mountain, cliff, rock and boulder file names elsewhere in it.
	bool IsRockPath(std::string_view a_canonical)
	{
		const bool inLandscape = a_canonical.starts_with("landscape/") || a_canonical.find("/landscape/") != std::string_view::npos;
		if (!inLandscape)
			return false;
		// Ground textures, even with "rock" in the name: AutoBlend's blend layers and grass/ground mixes
		if (a_canonical.find("landscape/blend/") != std::string_view::npos || a_canonical.find("landscape/grass/") != std::string_view::npos)
			return false;
		const auto separator = a_canonical.rfind('/');
		const auto fileName = separator == std::string_view::npos ? a_canonical : a_canonical.substr(separator + 1);
		// Hanging roots on dirt cliffs, and snow masks used in a diffuse slot, are not rock
		if (fileName.find("roots") != std::string_view::npos || fileName.find("mask") != std::string_view::npos)
			return false;
		if (a_canonical.find("landscape/mountains/") != std::string_view::npos || a_canonical.find("landscape/rocks/") != std::string_view::npos)
			return true;
		for (const std::string_view word : { "mountain", "cliff", "rock", "boulder" })
			if (fileName.find(word) != std::string_view::npos)
				return true;
		return false;
	}
}

#define I18N_KEY_PREFIX "feature.true_mountains."

void TrueMountains::DrawSettings()
{
	ImGui::Checkbox(T(TKEY("enabled"), "Enabled"), (bool*)&settings.Enabled);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("enabled_tooltip"), "Applies to meshes textured with landscape rock textures: mountains, cliffs and boulders."));
	}

	const Util::DisableGuard disabled(!settings.Enabled);

	ImGui::SliderFloat(T(TKEY("relief_shadows"), "Relief Shadows"), &settings.ReliefShadows, 0.0f, 1.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("relief_shadows_tooltip"), "Sunlight shadows cast by the rock's own cracks and ledges. Strongest when the sun is low. 0 turns them off."));
	}

	ImGui::SliderFloat(T(TKEY("relief_depth"), "Relief Depth"), &settings.ReliefDepth, 0.1f, 1.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("relief_depth_tooltip"), "How deep the rock relief is assumed to be: longer shadows. The height is guessed from the texture, so high values can look embossed."));
	}

	ImGui::SliderFloat(T(TKEY("cavity"), "Cavity"), &settings.Cavity, 0.0f, 1.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("cavity_tooltip"), "Darkens cracks and crevices, mostly in indirect light."));
	}

	ImGui::SliderFloat(T(TKEY("contrast"), "Contrast"), &settings.Contrast, 0.0f, 1.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("contrast_tooltip"), "Restores the detail and colour that washed-out rock textures lose."));
	}

	ImGui::SliderFloat(T(TKEY("color_variation"), "Colour Variation"), &settings.ColorVariation, 0.0f, 1.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("color_variation_tooltip"), "Large-scale warm and cool tint changes, so big rock faces do not repeat the same grey."));
	}

	ImGui::Checkbox(T(TKEY("debug_view"), "Debug View"), (bool*)&settings.DebugView);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("debug_view_tooltip"), "Paints detected rock red, darkened by its relief shadows. Rock that keeps its normal colour is not detected."));
	}
}

#undef I18N_KEY_PREFIX

void TrueMountains::LoadSettings(json& o_json)
{
	settings = o_json;
	settings.ReliefShadows = std::clamp(settings.ReliefShadows, 0.0f, 1.0f);
	settings.ReliefDepth = std::clamp(settings.ReliefDepth, 0.1f, 1.0f);
	settings.Cavity = std::clamp(settings.Cavity, 0.0f, 1.0f);
	settings.Contrast = std::clamp(settings.Contrast, 0.0f, 1.0f);
	settings.ColorVariation = std::clamp(settings.ColorVariation, 0.0f, 1.0f);
	settings.pad0 = 0.0f;
}

void TrueMountains::SaveSettings(json& o_json)
{
	o_json = settings;
}

void TrueMountains::RestoreDefaultSettings()
{
	settings = {};
}

bool TrueMountains::IsRockTexture(std::string_view a_path)
{
	if (a_path.empty())
		return false;

	{
		const std::shared_lock lock(textureMutex);
		if (auto it = textureCache.find(a_path); it != textureCache.end())
			return it->second;
	}

	const std::unique_lock lock(textureMutex);
	auto [it, inserted] = textureCache.try_emplace(std::string(a_path), false);
	if (inserted) {
		const auto canonical = CanonicaliseTexturePath(a_path);
		it->second = IsRockPath(canonical);
		// The first few results are logged at info level, so detection can be checked without the
		// debug log level (which deoptimizes shaders)
		if (it->second && ++loggedRockTextures <= MaxLoggedRockTextures)
			logger::info("TrueMountains: Rock texture {}", a_path);
		// Mountain or cliff textures the path rules miss
		if (!it->second && (canonical.find("mountain") != std::string::npos || canonical.find("cliff") != std::string::npos) && ++loggedMissedTextures <= MaxLoggedRockTextures)
			logger::info("TrueMountains: Not treated as rock: {}", a_path);
	}
	return it->second;
}

void TrueMountains::BSLightingShader_SetupGeometry(RE::BSRenderPass* a_pass)
{
	auto& descriptor = globals::state->permutationData.ExtraFeatureDescriptor;
	descriptor &= ~uint(State::ExtraFeatureDescriptors::TMRock);

	if (!loaded || !settings.Enabled || a_pass == nullptr || a_pass->geometry == nullptr)
		return;

	auto& runtimeData = a_pass->geometry->GetGeometryRuntimeData();

	auto& shaderProperty = runtimeData.shaderProperty;
	auto lightProperty = shaderProperty && shaderProperty->GetRTTI() == globals::rtti::BSLightingShaderPropertyRTTI.get() ? static_cast<RE::BSLightingShaderProperty*>(shaderProperty.get()) : nullptr;
	if (lightProperty == nullptr)
		return;

	// The diffuse path from the material's texture set: textures a mesh loads from its own .nif
	// carry no name on the texture object, only landscape and texture-set (TXST) textures do
	auto material = static_cast<RE::BSLightingShaderMaterialBase*>(lightProperty->material);
	if (material == nullptr)
		return;
	const char* path = material->textureSet ? material->textureSet->GetTexturePath(RE::BSTextureSet::Texture::kDiffuse) : nullptr;
	if ((path == nullptr || *path == '\0') && material->diffuseTexture)
		path = material->diffuseTexture->name.c_str();
	if (path == nullptr || !IsRockTexture(path))
		return;

	// Alpha-tested draws are foliage cards and decals sharing landscape folders
	auto& alphaProperty = runtimeData.alphaProperty;
	const bool alphaTested = alphaProperty && alphaProperty->GetRTTI() == globals::rtti::NiAlphaPropertyRTTI.get() && static_cast<RE::NiAlphaProperty*>(alphaProperty.get())->GetAlphaTesting();

	using enum RE::BSShaderProperty::EShaderPropertyFlag;
	const bool excludedType = lightProperty->flags.any(kMultiTextureLandscape, kLODLandscape, kLODObjects, kHDLODObjects, kDecal, kDynamicDecal, kSkinned);

	if (alphaTested || excludedType) {
		LogRejectedRock(path, alphaTested, lightProperty->flags.underlying());
		return;
	}
	descriptor |= uint(State::ExtraFeatureDescriptors::TMRock);
}

void TrueMountains::LogRejectedRock(std::string_view a_path, bool a_alphaTested, uint64_t a_flags)
{
	const std::unique_lock lock(textureMutex);
	if (loggedRejections >= MaxLoggedRockTextures || !rejectedLogged.emplace(a_path).second)
		return;
	++loggedRejections;
	logger::info("TrueMountains: Rock texture {} skipped (alpha tested {}, shader flags {:#x})", a_path, a_alphaTested, a_flags);
}

struct TrueMountains::Hooks
{
	struct BSLightingShader_SetupGeometry
	{
		static void thunk(RE::BSShader* This, RE::BSRenderPass* Pass, uint32_t RenderFlags)
		{
			globals::features::trueMountains.BSLightingShader_SetupGeometry(Pass);
			func(This, Pass, RenderFlags);
		}
		static inline REL::Relocation<decltype(thunk)> func;
	};

	static void Install()
	{
		stl::write_vfunc<0x6, BSLightingShader_SetupGeometry>(RE::VTABLE_BSLightingShader[0]);
		logger::info("TrueMountains: Installed hooks - BSLightingShader_SetupGeometry");
	}
};

void TrueMountains::PostPostLoad()
{
	Hooks::Install();
}
