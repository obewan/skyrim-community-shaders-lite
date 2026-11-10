#include "TrueClouds.h"

#include "I18n/I18n.h"
#include "Utils/UI.h"

NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_WITH_DEFAULT(
	TrueClouds::Settings,
	Enabled,
	SilverLining,
	SunGlow,
	Depth,
	SunTint,
	DebugView)

#define I18N_KEY_PREFIX "feature.true_clouds."

void TrueClouds::DrawSettings()
{
	ImGui::Checkbox(T(TKEY("enabled"), "Enabled"), (bool*)&settings.Enabled);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("enabled_tooltip"), "Lights the game's cloud layers from the sun by day and the moon by night. Weather cloud colours still apply."));
	}

	const Util::DisableGuard disabled(!settings.Enabled);

	ImGui::SliderFloat(T(TKEY("silver_lining"), "Silver Lining"), &settings.SilverLining, 0.0f, 2.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("silver_lining_tooltip"), "Bright rims on cloud edges in front of the sun or moon."));
	}

	ImGui::SliderFloat(T(TKEY("sun_glow"), "Sun Glow"), &settings.SunGlow, 0.0f, 2.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("sun_glow_tooltip"), "Light glowing through thin cloud close to the sun or moon."));
	}

	ImGui::SliderFloat(T(TKEY("depth"), "Depth"), &settings.Depth, 0.0f, 1.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("depth_tooltip"), "Darkens thick cloud, so heavy clouds look deep instead of flat grey."));
	}

	ImGui::SliderFloat(T(TKEY("sun_tint"), "Light Tint"), &settings.SunTint, 0.0f, 1.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("sun_tint_tooltip"), "Thin, lit cloud takes the colour of the light: golden at sunrise and sunset, silver under the moon."));
	}

	ImGui::Checkbox(T(TKEY("debug_view"), "Debug View"), (bool*)&settings.DebugView);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("debug_view_tooltip"), "Shows how clouds are read: red where an edge gets a silver lining, green where thin cloud glows, blue for thickness."));
	}
}

#undef I18N_KEY_PREFIX

void TrueClouds::LoadSettings(json& o_json)
{
	settings = o_json;
	settings.SilverLining = std::clamp(settings.SilverLining, 0.0f, 2.0f);
	settings.SunGlow = std::clamp(settings.SunGlow, 0.0f, 2.0f);
	settings.Depth = std::clamp(settings.Depth, 0.0f, 1.0f);
	settings.SunTint = std::clamp(settings.SunTint, 0.0f, 1.0f);
	settings.pad0 = settings.pad1 = 0.0f;
}

void TrueClouds::SaveSettings(json& o_json)
{
	o_json = settings;
}

void TrueClouds::RestoreDefaultSettings()
{
	settings = {};
}
