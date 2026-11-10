#ifndef TRUE_MOUNTAINS_HLSLI
#define TRUE_MOUNTAINS_HLSLI

#include "Common/Color.hlsli"
#include "Common/FrameBuffer.hlsli"
#include "Common/Permutation.hlsli"
#include "Common/SharedData.hlsli"

/**
 * True Mountains: rock shading for draws flagged as rock by the C++ side (landscape rock textures on
 * mountains, cliffs and boulders). Vanilla rock has no height map, so a height is guessed from the
 * diffuse texture's luminance relative to its local average: dark cracks are low, bright faces high.
 * Settings come from the spare FeatureData slots, so this file is the only shader code that knows them.
 */
namespace TrueMountains
{
	/// First spare slot; must match TrueMountains::SpareSlot in src/Features/TrueMountains.h.
	static const uint SpareSlot = 0;
	/// Per-draw flag; must match State::ExtraFeatureDescriptors::TMRock.
	static const uint RockFlag = (1 << 11);

	/// Shadow ray samples toward the sun.
	static const uint ShadowSteps = 6;
	/// Height comes from a slightly blurred mip: rock shapes, not texture grain.
	static const float HeightMipBias = 1.0;
	/// Mips above the current one that give the local average colour.
	static const float AverageMipOffset = 3.0;
	/// UV reach of the shadow ray per unit of height at Relief Depth 1.
	static const float MaxUVReach = 0.05;
	/// How sharply an occluder above the ray turns into shadow.
	static const float ShadowSharpness = 6.0;
	/// Relief shading fades out on far, heavily minified rock, where it would only add noise.
	static const float FadeStartMip = 5.0;
	static const float FadeEndMip = 8.0;
	/// Share of the cavity darkening applied to the albedo; the rest only darkens indirect light.
	static const float CavityAlbedoShare = 0.35;
	/// Strongest darkening of a full cavity at Cavity 1.
	static const float CavityMax = 0.7;
	/// Size of the colour variation patches, in world units (about 85 m).
	static const float VariationScale = 1.0 / 6000.0;
	static const float3 WarmTint = float3(1.07, 1.0, 0.91);
	static const float3 CoolTint = float3(0.93, 0.98, 1.07);

	struct Settings
	{
		bool Enabled;
		float ReliefShadows;
		float ReliefDepth;
		float Cavity;
		float Contrast;
		float ColorVariation;
		bool DebugView;
	};

	Settings GetSettings()
	{
		const float4 s0 = SharedData::SpareSlots[SpareSlot];
		const float4 s1 = SharedData::SpareSlots[SpareSlot + 1];
		Settings s;
		s.Enabled = asuint(s0.x) != 0;
		s.ReliefShadows = s0.y;
		s.ReliefDepth = s0.z;
		s.Cavity = s0.w;
		s.Contrast = s1.x;
		s.ColorVariation = s1.y;
		s.DebugView = asuint(s1.z) != 0;
		return s;
	}

	/// True when this draw is rock and the feature is on.
	bool IsRock()
	{
		return (Permutation::ExtraFeatureDescriptor & RockFlag) != 0 && asuint(SharedData::SpareSlots[SpareSlot].x) != 0;
	}

	float Luma(float3 color)
	{
		return dot(color, float3(0.2126, 0.7152, 0.0722));
	}

	/// What the rock shading needs about the texture around this pixel, sampled once.
	struct Surface
	{
		float Lod;            ///< Mip level of the diffuse texture here.
		float3 AverageColor;  ///< Local average colour (a few mips up).
		float AverageLuma;
		float Height;  ///< Guessed height of this pixel, 0..1.
		float Fade;    ///< 1 near, 0 on far minified rock.
	};

	/// Guessed height of a texel: luminance relative to the local average, centred on 0.5.
	float HeightFromLuma(float luma, float averageLuma)
	{
		return saturate(0.5 + 1.5 * (luma - averageLuma) / max(averageLuma, 0.05));
	}

	Surface GetSurface(Texture2D<float4> tex, SamplerState samp, float2 uv)
	{
		Surface surface;
		surface.Lod = tex.CalculateLevelOfDetail(samp, uv);
		surface.AverageColor = Color::Albedo(tex.SampleLevel(samp, uv, surface.Lod + AverageMipOffset).rgb);
		surface.AverageLuma = Luma(surface.AverageColor);
		surface.Height = HeightFromLuma(Luma(Color::Albedo(tex.SampleLevel(samp, uv, surface.Lod + HeightMipBias).rgb)), surface.AverageLuma);
		surface.Fade = 1.0 - smoothstep(FadeStartMip, FadeEndMip, surface.Lod);
		return surface;
	}

	/// Smooth 2D value noise, 0..1.
	float ValueNoise(float2 p)
	{
		const float2 i = floor(p);
		const float2 f = frac(p);
		const float2 u = f * f * (3.0 - 2.0 * f);
		const float4 h = frac(sin(float4(dot(i, float2(127.1, 311.7)), dot(i + float2(1, 0), float2(127.1, 311.7)),
								  dot(i + float2(0, 1), float2(127.1, 311.7)), dot(i + float2(1, 1), float2(127.1, 311.7)))) *
							  43758.5453);
		return lerp(lerp(h.x, h.y, u.x), lerp(h.z, h.w, u.x), u.y);
	}

	/**
	 * Rock albedo: restored contrast and saturation around the local average, darkened cavities and
	 * large-scale warm/cool variation. Returns the cavity occlusion for indirect light in `cavityAO`.
	 */
	float3 AdjustAlbedo(float3 albedo, Surface surface, float3 worldPosition, Settings s, out float cavityAO)
	{
		// Contrast around the local average, and a little of the saturation grey textures lost
		float3 color = max(0, surface.AverageColor + (albedo - surface.AverageColor) * (1.0 + s.Contrast * surface.Fade));
		color = max(0, lerp(Luma(color).xxx, color, 1.0 + 0.3 * s.Contrast));

		// Texels darker than their surroundings are cracks and crevices
		const float cavity = saturate(2.0 * (surface.AverageLuma - Luma(albedo)) / max(surface.AverageLuma, 0.05)) * s.Cavity * CavityMax * surface.Fade;
		cavityAO = 1.0 - cavity;
		color *= 1.0 - cavity * CavityAlbedoShare;

		const float3 absolutePosition = worldPosition + FrameBuffer::CameraPosAdjust.xyz;
		const float variation = ValueNoise(absolutePosition.xy * VariationScale) * 0.7 + ValueNoise(absolutePosition.xy * VariationScale * 3.7 + absolutePosition.z * VariationScale) * 0.3;
		color *= lerp(1.0.xxx, lerp(WarmTint, CoolTint, variation), s.ColorVariation);
		return color;
	}

	/**
	 * Sun shadow cast by the rock's own relief: marches the guessed height field from this texel
	 * toward the light, in UV space, as Extended Materials does with real height maps.
	 * @param lightTS Light direction in tangent space (mul(lightDirection, tbn)).
	 */
	float ReliefShadow(Texture2D<float4> tex, SamplerState samp, float2 uv, Surface surface, float3 lightTS, float noise, Settings s)
	{
		const float strength = s.ReliefShadows * surface.Fade;
		float occlusion = 0.0;
		[branch] if (strength > 0.0 && lightTS.z > 0.0)
		{
			// UV offset per unit of height climbed toward the light; grazing light reaches farther
			const float2 uvPerHeight = lightTS.xy / max(lightTS.z, 0.15) * (MaxUVReach * s.ReliefDepth);
			const float heightLod = surface.Lod + HeightMipBias;
			const float climb = 1.0 - surface.Height;
			[unroll] for (uint i = 1; i <= ShadowSteps; i++)
			{
				const float rise = climb * (float(i) - noise) / ShadowSteps;
				const float sampleHeight = HeightFromLuma(Luma(Color::Albedo(tex.SampleLevel(samp, uv + uvPerHeight * rise, heightLod).rgb)), surface.AverageLuma);
				occlusion = max(occlusion, (sampleHeight - (surface.Height + rise)) * ShadowSharpness);
			}
		}
		return 1.0 - saturate(occlusion) * strength;
	}
}

#endif  // TRUE_MOUNTAINS_HLSLI
