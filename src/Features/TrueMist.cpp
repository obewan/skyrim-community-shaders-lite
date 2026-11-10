#include "TrueMist.h"

#include "I18n/I18n.h"
#include "State.h"
#include "Utils/UI.h"

NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_WITH_DEFAULT(
	TrueMist::Settings,
	Enabled,
	SunScattering,
	AmbientTint,
	Breakup,
	ThinFromAbove,
	NearFade,
	DebugView,
	Glints)

namespace
{
	/// File name, lower-case, without folders.
	std::string LowerFileName(std::string_view a_path)
	{
		const auto separator = a_path.find_last_of("/\\");
		std::string name(separator == std::string_view::npos ? a_path : a_path.substr(separator + 1));
		for (auto& character : name)
			character = static_cast<char>(std::tolower(static_cast<unsigned char>(character)));
		return name;
	}

	/// Mist, steam, fog, vapor and spray textures and gradients, such as Realistic Water Two's
	/// water_mistloop, vaportile and water_gradfogskirt. Waterfall streams and foam do not match.
	bool IsMistName(std::string_view a_fileName)
	{
		for (const std::string_view word : { "mist", "steam", "fog", "vapor", "spray" })
			if (a_fileName.find(word) != std::string_view::npos)
				return true;
		return false;
	}
}

#define I18N_KEY_PREFIX "feature.true_mist."

void TrueMist::DrawSettings()
{
	ImGui::Checkbox(T(TKEY("enabled"), "Enabled"), (bool*)&settings.Enabled);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("enabled_tooltip"), "Applies to effects textured as mist, steam, fog, vapor or spray: river fog, waterfall mist, hot springs."));
	}

	const Util::DisableGuard disabled(!settings.Enabled);

	ImGui::SliderFloat(T(TKEY("sun_scattering"), "Sun Scattering"), &settings.SunScattering, 0.0f, 2.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("sun_scattering_tooltip"), "How brightly sunlit mist shines: white in direct sun from any side, glowing when you look toward the sun through it. Shadows block it."));
	}

	ImGui::SliderFloat(T(TKEY("glints"), "Droplet Glints"), &settings.Glints, 0.0f, 2.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("glints_tooltip"), "Water droplets twinkling where the sun hits the mist. 0 turns them off."));
	}

	ImGui::SliderFloat(T(TKEY("ambient_tint"), "Sky Tint"), &settings.AmbientTint, 0.0f, 1.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("ambient_tint_tooltip"), "Takes on the colour of the sky's light instead of flat grey: bluish under a clear sky, warm at sunset."));
	}

	ImGui::SliderFloat(T(TKEY("breakup"), "Wisps"), &settings.Breakup, 0.0f, 1.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("breakup_tooltip"), "Breaks the flat mist sprites into slowly drifting wisps."));
	}

	ImGui::SliderFloat(T(TKEY("thin_from_above"), "Thin From Above"), &settings.ThinFromAbove, 0.0f, 1.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("thin_from_above_tooltip"), "Makes mist more see-through when looking down at it, so the water and rocks below stay visible."));
	}

	ImGui::SliderFloat(T(TKEY("near_fade"), "Near Fade"), &settings.NearFade, 0.0f, 1500.0f, "%.0f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("near_fade_tooltip"), "Distance, in game units, over which mist fades out in front of the camera, so it never becomes a grey wall. 0 turns it off."));
	}

	ImGui::Checkbox(T(TKEY("debug_view"), "Debug View"), (bool*)&settings.DebugView);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("debug_view_tooltip"), "Paints detected mist blue. Mist that keeps its normal colour is not detected."));
	}
}

#undef I18N_KEY_PREFIX

void TrueMist::LoadSettings(json& o_json)
{
	settings = o_json;
	settings.SunScattering = std::clamp(settings.SunScattering, 0.0f, 2.0f);
	settings.AmbientTint = std::clamp(settings.AmbientTint, 0.0f, 1.0f);
	settings.Breakup = std::clamp(settings.Breakup, 0.0f, 1.0f);
	settings.ThinFromAbove = std::clamp(settings.ThinFromAbove, 0.0f, 1.0f);
	settings.NearFade = std::clamp(settings.NearFade, 0.0f, 1500.0f);
	settings.Glints = std::clamp(settings.Glints, 0.0f, 2.0f);
}

void TrueMist::SaveSettings(json& o_json)
{
	o_json = settings;
}

void TrueMist::RestoreDefaultSettings()
{
	settings = {};
}

bool TrueMist::IsMistTexture(std::string_view a_path)
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
		it->second = IsMistName(LowerFileName(a_path));
		// The first matches are logged at info level, so detection can be checked without the
		// debug log level (which deoptimizes shaders)
		if (it->second && ++loggedTextures <= MaxLoggedTextures)
			logger::info("TrueMist: Mist texture {}", a_path);
	}
	return it->second;
}

void TrueMist::BSEffectShader_SetupGeometry(RE::BSRenderPass* a_pass)
{
	auto& descriptor = globals::state->permutationData.ExtraFeatureDescriptor;
	descriptor &= ~uint(State::ExtraFeatureDescriptors::TrueMist);

	if (!loaded || !settings.Enabled || a_pass == nullptr || a_pass->shaderProperty == nullptr)
		return;

	auto property = a_pass->shaderProperty->GetRTTI() == globals::rtti::BSEffectShaderPropertyRTTI.get() ?
                        static_cast<RE::BSEffectShaderProperty*>(a_pass->shaderProperty) :
                        nullptr;
	if (property == nullptr)
		return;
	auto material = static_cast<RE::BSEffectShaderMaterial*>(property->GetMaterial());
	if (material == nullptr)
		return;

	if (IsMistTexture(material->sourceTexturePath.c_str()) || IsMistTexture(material->greyscaleTexturePath.c_str()))
		descriptor |= uint(State::ExtraFeatureDescriptors::TrueMist);
}

struct TrueMist::Hooks
{
	struct BSEffectShader_SetupGeometry
	{
		static void thunk(RE::BSShader* This, RE::BSRenderPass* Pass, uint32_t RenderFlags)
		{
			globals::features::trueMist.BSEffectShader_SetupGeometry(Pass);
			func(This, Pass, RenderFlags);
		}
		static inline REL::Relocation<decltype(thunk)> func;
	};

	static void Install()
	{
		stl::write_vfunc<0x6, BSEffectShader_SetupGeometry>(RE::VTABLE_BSEffectShader[0]);
		logger::info("TrueMist: Installed hooks - BSEffectShader_SetupGeometry");
	}
};

void TrueMist::PostPostLoad()
{
	Hooks::Install();
}
