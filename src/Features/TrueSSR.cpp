#include "TrueSSR.h"

#include "Deferred.h"
#include "Features/TerrainBlending.h"
#include "I18n/I18n.h"
#include "State.h"
#include "Util.h"

NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_WITH_DEFAULT(
	TrueSSR::Settings,
	Enabled,
	ResolutionMode,
	MaxSteps,
	MaxDistance,
	Thickness,
	RoughnessCutoff,
	Intensity,
	EdgeFade)

namespace
{
	constexpr uint kMinSteps = 8;
	constexpr uint kMaxSteps = 64;
}

#define I18N_KEY_PREFIX "feature.true_ssr."

void TrueSSR::DrawSettings()
{
	ImGui::Checkbox(T(TKEY("enabled"), "Enabled"), &settings.Enabled);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("enabled_tooltip"), "Traces reflections for reflective deferred surfaces. Where nothing on screen is hit, Dynamic Cubemaps reflections remain."));
	}

	const Util::DisableGuard disabled(!settings.Enabled);

	ImGui::TextUnformatted(T(TKEY("resolution"), "Resolution"));
	ImGui::SameLine();
	ImGui::RadioButton(T(TKEY("full_res"), "Full"), &settings.ResolutionMode, 0);
	ImGui::SameLine();
	ImGui::RadioButton(T(TKEY("half_res"), "Half"), &settings.ResolutionMode, 1);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("resolution_tooltip"), "Half resolution costs about a quarter of full resolution."));
	}

	int steps = static_cast<int>(settings.MaxSteps);
	if (ImGui::SliderInt(T(TKEY("max_steps"), "Max Steps"), &steps, static_cast<int>(kMinSteps), static_cast<int>(kMaxSteps), "%d", ImGuiSliderFlags_AlwaysClamp))
		settings.MaxSteps = static_cast<uint>(steps);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("max_steps_tooltip"), "Samples along each reflection ray. More steps find thinner and farther objects, at a GPU cost."));
	}

	ImGui::SliderFloat(T(TKEY("max_distance"), "Max Distance"), &settings.MaxDistance, 500.0f, 10000.0f, "%.0f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("max_distance_tooltip"), "How far a reflection ray travels, in game units."));
	}

	ImGui::SliderFloat(T(TKEY("thickness"), "Thickness"), &settings.Thickness, 5.0f, 200.0f, "%.0f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("thickness_tooltip"), "How thick objects are assumed to be behind their visible surface.\nLower values avoid false reflections; higher values close gaps."));
	}

	ImGui::SliderFloat(T(TKEY("roughness_cutoff"), "Roughness Cutoff"), &settings.RoughnessCutoff, 0.1f, 1.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("roughness_cutoff_tooltip"), "Surfaces rougher than this keep Dynamic Cubemaps reflections; smoother ones fade into screen-space reflections."));
	}

	ImGui::SliderFloat(T(TKEY("intensity"), "Intensity"), &settings.Intensity, 0.0f, 1.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("intensity_tooltip"), "How much screen-space reflections replace the cubemap where they are found."));
	}

	ImGui::SliderFloat(T(TKEY("edge_fade"), "Edge Fade"), &settings.EdgeFade, 0.01f, 0.5f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("edge_fade_tooltip"), "Fraction of the screen over which reflections fade out near its borders."));
	}
}

#undef I18N_KEY_PREFIX

void TrueSSR::LoadSettings(json& o_json)
{
	settings = o_json;
	settings.ResolutionMode = std::clamp(settings.ResolutionMode, 0, 1);
	settings.MaxSteps = std::clamp(settings.MaxSteps, kMinSteps, kMaxSteps);
	settings.MaxDistance = std::clamp(settings.MaxDistance, 500.0f, 10000.0f);
	settings.Thickness = std::clamp(settings.Thickness, 5.0f, 200.0f);
	settings.RoughnessCutoff = std::clamp(settings.RoughnessCutoff, 0.1f, 1.0f);
	settings.Intensity = std::clamp(settings.Intensity, 0.0f, 1.0f);
	settings.EdgeFade = std::clamp(settings.EdgeFade, 0.01f, 0.5f);
}

void TrueSSR::SaveSettings(json& o_json)
{
	o_json = settings;
}

void TrueSSR::RestoreDefaultSettings()
{
	settings = {};
}

void TrueSSR::SetupResources()
{
	constantBuffer = eastl::make_unique<ConstantBuffer>(ConstantBufferDesc<TrueSSRCB>(), "TrueSSR::CB");
}

void TrueSSR::ClearShaderCache()
{
	computeShader = nullptr;
}

ID3D11ComputeShader* TrueSSR::GetComputeShader()
{
	if (!computeShader) {
		std::vector<std::pair<const char*, const char*>> defines;
		// The depth SRV's type differs with Terrain Blending, as in DeferredCompositeCS
		if (globals::features::terrainBlending.loaded)
			defines.push_back({ "TERRAIN_BLENDING", nullptr });
		if (auto shader = static_cast<ID3D11ComputeShader*>(Util::CompileShader(L"Data\\Shaders\\TrueSSR\\TrueSSR.cs.hlsl", defines, "cs_5_0")))
			computeShader.attach(shader);
		else
			logger::error("[True SSR] Failed to compile TrueSSR.cs.hlsl, reflections fall back to Dynamic Cubemaps");
	}
	return computeShader.get();
}

void TrueSSR::EnsureOutput(uint a_scale)
{
	const auto& mainTarget = globals::game::renderer->GetRuntimeData().renderTargets[RE::RENDER_TARGETS::kMAIN];
	D3D11_TEXTURE2D_DESC mainDesc;
	mainTarget.texture->GetDesc(&mainDesc);
	const uint width = (mainDesc.Width + a_scale - 1) / a_scale;
	const uint height = (mainDesc.Height + a_scale - 1) / a_scale;

	if (output && outputScale == a_scale) {
		D3D11_TEXTURE2D_DESC currentDesc;
		output->resource->GetDesc(&currentDesc);
		if (currentDesc.Width == width && currentDesc.Height == height)
			return;
	}

	D3D11_TEXTURE2D_DESC desc{
		.Width = width,
		.Height = height,
		.MipLevels = 1,
		.ArraySize = 1,
		.Format = DXGI_FORMAT_R16G16B16A16_FLOAT,
		.SampleDesc = { 1, 0 },
		.Usage = D3D11_USAGE_DEFAULT,
		.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS,
		.CPUAccessFlags = 0,
		.MiscFlags = 0
	};
	output = eastl::make_unique<Texture2D>(desc, "TrueSSR::Output");
	output->CreateSRV({ .Format = desc.Format, .ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D, .Texture2D = { .MostDetailedMip = 0, .MipLevels = 1 } });
	output->CreateUAV({ .Format = desc.Format, .ViewDimension = D3D11_UAV_DIMENSION_TEXTURE2D, .Texture2D = { .MipSlice = 0 } });
	outputScale = a_scale;
}

void TrueSSR::Draw(ID3D11ShaderResourceView* a_depth, ID3D11ShaderResourceView* a_normalRoughness, ID3D11ShaderResourceView* a_reflectance,
	ID3D11ShaderResourceView* a_main, ID3D11ShaderResourceView* a_specular)
{
	drawnThisFrame = false;
	if (!settings.Enabled || !constantBuffer || !a_depth || !a_normalRoughness || !a_reflectance || !a_main || !a_specular)
		return;

	auto shader = GetComputeShader();
	if (!shader)
		return;

	const uint scale = settings.ResolutionMode == 0 ? 1u : 2u;
	EnsureOutput(scale);

	const float2 size = Util::ConvertToDynamic(float2{ (float)globals::game::graphicsState->screenWidth, (float)globals::game::graphicsState->screenHeight });
	const uint outputWidth = ((uint)size.x + scale - 1) / scale;
	const uint outputHeight = ((uint)size.y + scale - 1) / scale;

	TrueSSRCB data{
		.OutputDim = { outputWidth, outputHeight },
		.ResolutionScale = scale,
		.MaxSteps = settings.MaxSteps,
		.MaxDistance = settings.MaxDistance,
		.Thickness = settings.Thickness,
		.RoughnessCutoff = settings.RoughnessCutoff,
		.Intensity = settings.Intensity,
		.EdgeFade = settings.EdgeFade,
		// Animated jitter only when TAA resolves it, as for Screen Space GI
		.FrameIndex = Util::GetTemporal() ? globals::state->frameCount : 0u
	};
	constantBuffer->Update(data);

	auto context = globals::d3d::context;
	auto cb = constantBuffer->CB();
	context->CSSetConstantBuffers(0, 1, &cb);
	auto* sharedDataBuffer = globals::state->sharedDataCB->CB();
	context->CSSetConstantBuffers(5, 1, &sharedDataBuffer);
	context->CSSetSamplers(0, 1, &globals::deferred->linearSampler);

	ID3D11ShaderResourceView* srvs[5]{ a_depth, a_normalRoughness, a_reflectance, a_main, a_specular };
	context->CSSetShaderResources(0, ARRAYSIZE(srvs), srvs);
	ID3D11UnorderedAccessView* uav = output->uav.get();
	context->CSSetUnorderedAccessViews(0, 1, &uav, nullptr);
	context->CSSetShader(shader, nullptr, 0);

	globals::profiler->BeginPass("TrueSSR");
	context->Dispatch((outputWidth + 7) / 8, (outputHeight + 7) / 8, 1);
	globals::profiler->EndPass();

	ID3D11ShaderResourceView* nullSrvs[5]{};
	context->CSSetShaderResources(0, ARRAYSIZE(nullSrvs), nullSrvs);
	ID3D11UnorderedAccessView* nullUav = nullptr;
	context->CSSetUnorderedAccessViews(0, 1, &nullUav, nullptr);
	ID3D11Buffer* nullCb = nullptr;
	context->CSSetConstantBuffers(0, 1, &nullCb);
	context->CSSetShader(nullptr, nullptr, 0);

	drawnThisFrame = true;
}
