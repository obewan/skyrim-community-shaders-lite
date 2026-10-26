#pragma once

#include "Buffer.h"

/**
 * @brief Per-pixel screen-space reflections for deferred surfaces.
 *
 * A compute pass between Screen Space GI and the deferred composite marches each reflective
 * pixel's reflection ray against the depth buffer, using the G-buffer's per-pixel normal and
 * roughness. It writes the reflected radiance and a confidence; DeferredCompositeCS blends that
 * over the Dynamic Cubemaps / IBL environment lookup, which stays the fallback wherever a ray
 * misses, leaves the screen or the surface is too rough. Water keeps the game's own reflections.
 */
struct TrueSSR : Feature
{
public:
	virtual inline std::string GetName() override { return "True SSR"; }
	virtual std::string GetDisplayName() override { return T("feature.true_ssr.name", "True SSR"); }
	virtual inline std::string GetShortName() override { return "TrueSSR"; }
	virtual inline std::string_view GetShaderDefineName() override { return "TRUE_SSR"; }
	virtual std::string_view GetCategory() const override { return FeatureCategories::kLighting; }

	virtual std::pair<std::string, std::vector<std::string>> GetFeatureSummary() override
	{
		return { T("feature.true_ssr.description", "Screen-space reflections that follow each surface's own normal and roughness, falling back to Dynamic Cubemaps where the screen has no answer."),
			{ T("feature.true_ssr.key_feature_1", "Per-pixel reflections from the G-buffer normals, not one flat plane"),
				T("feature.true_ssr.key_feature_2", "Mirror-like surfaces reflect sharply; rough ones fade to the cubemap"),
				T("feature.true_ssr.key_feature_3", "Smooth fade at screen edges, distance and rays facing the camera"),
				T("feature.true_ssr.key_feature_4", "Half resolution by default, adjustable step count") } };
	}

	/** @brief User settings. */
	struct Settings
	{
		bool Enabled = true;
		int ResolutionMode = 1;  // 0 = full, 1 = half
		uint MaxSteps = 24;
		float MaxDistance = 3000.0f;
		float Thickness = 40.0f;
		float RoughnessCutoff = 0.6f;
		float Intensity = 1.0f;
		float EdgeFade = 0.1f;
		float ReflectionStrength = 1.0f;
		float BaseReflectance = 0.04f;
		float BaseRoughness = 0.25f;
		bool DebugView = false;
	} settings;

	/** @brief Feature buffer data for DeferredCompositeCS, matching TrueSSRSettings in SharedData.hlsli. */
	struct alignas(16) PerFrame
	{
		float ReflectionStrength;
		uint DebugView;
		float BaseReflectance;
		float pad0;
	};
	STATIC_ASSERT_ALIGNAS_16(PerFrame);

	/** @brief Composite-side settings for the feature buffer. */
	PerFrame GetCommonBufferData() const
	{
		return { .ReflectionStrength = settings.ReflectionStrength, .DebugView = settings.DebugView ? 1u : 0u, .BaseReflectance = settings.Enabled ? settings.BaseReflectance : 0.0f };
	}

	/** @brief Constant buffer for TrueSSR.cs.hlsl, matching TrueSSRCB. */
	struct alignas(16) TrueSSRCB
	{
		uint OutputDim[2];
		uint ResolutionScale;
		uint MaxSteps;
		float MaxDistance;
		float Thickness;
		float RoughnessCutoff;
		float Intensity;
		float EdgeFade;
		uint FrameIndex;
		float BaseReflectance;
		float BaseRoughness;
	};
	STATIC_ASSERT_ALIGNAS_16(TrueSSRCB);

	virtual void SetupResources() override;
	virtual void ClearShaderCache() override;
	virtual void RestoreDefaultSettings() override;
	virtual void LoadSettings(json& o_json) override;
	virtual void SaveSettings(json& o_json) override;
	virtual void DrawSettings() override;

	/**
	 * @brief Traces this frame's reflections; called by the deferred pipeline before the composite.
	 * @param a_depth Final scene depth.
	 * @param a_normalRoughness G-buffer view-space normal (xy) and glossiness (z).
	 * @param a_reflectance G-buffer reflectance; pixels with none are skipped.
	 * @param a_main Lit diffuse before the composite, in scene colour space.
	 * @param a_specular Direct specular, linear.
	 */
	void Draw(ID3D11ShaderResourceView* a_depth, ID3D11ShaderResourceView* a_normalRoughness, ID3D11ShaderResourceView* a_reflectance,
		ID3D11ShaderResourceView* a_main, ID3D11ShaderResourceView* a_specular);

	/** @brief The reflections traced this frame, or nullptr when the pass did not run (the composite then keeps the cubemap). */
	ID3D11ShaderResourceView* GetOutputSRV() const { return drawnThisFrame && output ? output->srv.get() : nullptr; }

private:
	ID3D11ComputeShader* GetComputeShader();
	/** @brief (Re)creates the output texture for the current resolution mode and screen size. */
	void EnsureOutput(uint a_scale);

	eastl::unique_ptr<Texture2D> output;
	uint outputScale = 0;
	eastl::unique_ptr<ConstantBuffer> constantBuffer;
	winrt::com_ptr<ID3D11ComputeShader> computeShader;
	bool drawnThisFrame = false;
};
