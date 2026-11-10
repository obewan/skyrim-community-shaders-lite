#ifndef TRUE_MIST_HLSLI
#define TRUE_MIST_HLSLI

#include "Common/Color.hlsli"
#include "Common/FrameBuffer.hlsli"
#include "Common/Math.hlsli"
#include "Common/Permutation.hlsli"
#include "Common/ShadowSampling.hlsli"
#include "Common/SharedData.hlsli"

/**
 * True Mist: shading for effect draws flagged as mist by the C++ side (mist, steam, fog, vapor and
 * spray textures, e.g. Realistic Water Two's river fog skirts and waterfall mist). Adds shadowed
 * forward sun scattering, tints by the sky's ambient colour, erodes the sprite into drifting wisps,
 * and thins it from above and near the camera. Settings come from the spare FeatureData slots.
 */
namespace TrueMist
{
	/// First spare slot; must match TrueMist::SpareSlot in src/Features/TrueMist.h.
	static const uint SpareSlot = 2;
	/// Per-draw flag; must match State::ExtraFeatureDescriptors::TrueMist.
	static const uint MistFlag = (1 << 12);

	/// Henyey-Greenstein asymmetry of water droplets: strongly forward scattering.
	static const float Anisotropy = 0.6;
	/// Scales the phase function's forward lobe (above isotropic) into added light.
	static const float ScatterScale = 0.08;
	/// Sunlight every droplet scatters in all directions: sunlit mist turns white from any side.
	static const float SunlitScale = 0.35;
	/// Droplet glint cell size, in game units: at most one glinting droplet per cell.
	static const float GlintCell = 6.0;
	/// Glinting droplet radius, in game units, before the one-pixel minimum.
	static const float GlintRadius = 0.6;
	/// Angular size of a screen pixel at 1080p and a 70 degree field of view, in radians.
	static const float PixelAngle = 0.0013;
	/// Fraction of cells holding a droplet that glints.
	static const float GlintCoverage = 0.3;
	/// Glints fade out beyond this distance, where they would only shimmer.
	static const float GlintMaxDistance = 4000.0;
	/// Twinkle rate, in radians per second.
	static const float TwinkleRate = 3.0;
	/// Brightness of a glint at Droplet Glints 1.
	static const float GlintGain = 6.0;
	/// Strongest thinning when looking straight down, at Thin From Above 1.
	static const float MaxAboveThinning = 0.75;
	/// Wisp noise frequency, per game unit (about 4 m features).
	static const float BreakupScale = 1.0 / 300.0;
	/// Wisp drift, in noise units per second.
	static const float DriftSpeed = 0.04;

	struct Settings
	{
		bool Enabled;
		float SunScattering;
		float AmbientTint;
		float Breakup;
		float ThinFromAbove;
		float NearFade;
		bool DebugView;
		float Glints;
	};

	Settings GetSettings()
	{
		const float4 s0 = SharedData::SpareSlots[SpareSlot];
		const float4 s1 = SharedData::SpareSlots[SpareSlot + 1];
		Settings s;
		s.Enabled = asuint(s0.x) != 0;
		s.SunScattering = s0.y;
		s.AmbientTint = s0.z;
		s.Breakup = s0.w;
		s.ThinFromAbove = s1.x;
		s.NearFade = s1.y;
		s.DebugView = asuint(s1.z) != 0;
		s.Glints = s1.w;
		return s;
	}

	/// True when this draw is mist and the feature is on.
	bool IsMist()
	{
		return (Permutation::ExtraFeatureDescriptor & MistFlag) != 0 && asuint(SharedData::SpareSlots[SpareSlot].x) != 0;
	}

	float Luma(float3 color)
	{
		return dot(color, float3(0.2126, 0.7152, 0.0722));
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

	/// Hash of a 3D cell, 0..1 per component.
	float3 Hash3(float3 cell)
	{
		return frac(sin(float3(dot(cell, float3(127.1, 311.7, 74.7)), dot(cell, float3(269.5, 183.3, 246.1)), dot(cell, float3(113.5, 271.9, 124.6)))) * 43758.5453);
	}

	/**
	 * Twinkling droplet glint at this point, 0..1: one droplet at a hashed spot in some world cells,
	 * at least about a pixel wide on screen, blinking at its own phase.
	 * @param absolutePosition World position (not camera-relative).
	 * @param distance Distance from the camera.
	 */
	float Glint(float3 absolutePosition, float distance)
	{
		const float3 cell = floor(absolutePosition / GlintCell);
		const float3 h = Hash3(cell);
		float glint = 0.0;
		[branch] if (h.z <= GlintCoverage)
		{
			const float3 droplet = (cell + 0.2 + 0.6 * Hash3(cell + 17.0)) * GlintCell;
			const float radius = max(GlintRadius, distance * PixelAngle * 1.5);
			const float core = saturate(1.0 - length(absolutePosition - droplet) / radius);
			const float twinkle = pow(saturate(sin(SharedData::Timer * TwinkleRate * (0.6 + h.y) + h.x * Math::TAU)), 6.0);
			glint = core * core * twinkle * saturate(1.0 - distance / GlintMaxDistance);
		}
		return glint;
	}

	/// Henyey-Greenstein phase function, scaled so isotropic scattering is 1.
	float Phase(float cosTheta, float g)
	{
		const float g2 = g * g;
		return (1.0 - g2) / pow(max(1.0 + g2 - 2.0 * g * cosTheta, 1e-4), 1.5);
	}

	/**
	 * Mist colour: the vanilla colour tinted toward the sky ambient's hue (brightness kept), plus
	 * sunlight scattered by the droplets where the sun reaches this point (in all directions, and
	 * more toward the sun), and twinkling droplet glints.
	 * @param color Vanilla lit effect colour, before Color::EffectMult.
	 * @param worldPosition Camera-relative world position.
	 * @param glint Receives the glint strength here, 0..1, so the caller can raise the opacity.
	 */
	float3 Shade(float3 color, float3 worldPosition, Settings s, out float glint)
	{
		glint = 0.0;
		const float luma = Luma(color);

		// The hue of the sky's light from above, at the vanilla brightness
		const float3 ambient = max(SharedData::GetAmbient(float3(0, 0, 1)), 0.0);
		const float ambientLuma = Luma(ambient);
		const float3 ambientHue = ambientLuma > 1e-4 ? clamp(ambient / ambientLuma, 0.0, 2.0) : 1.0.xxx;
		float3 shaded = color * lerp(1.0.xxx, ambientHue, s.AmbientTint);

		[branch] if (!SharedData::InInterior && (s.SunScattering > 0.0 || s.Glints > 0.0))
		{
			const float distance = length(worldPosition);
			const float3 viewDirection = worldPosition / max(distance, 1e-3);
			const float forward = max(Phase(dot(viewDirection, SharedData::DirLightDirection.xyz), Anisotropy) - 1.0, 0.0);
			float detailedShadow;
			const float shadow = ShadowSampling::GetLightingShadow(worldPosition, detailedShadow);
			const float3 sun = Color::DirectionalLight(SharedData::DirLightColor.xyz) * shadow;
			shaded += luma * sun * (SunlitScale + forward * ScatterScale) * s.SunScattering;

			[branch] if (s.Glints > 0.0 && shadow > 0.0)
			{
				glint = Glint(worldPosition + FrameBuffer::CameraPosAdjust.xyz, distance) * s.Glints;
				// Droplets glint brightest toward the sun, but catch it from any side
				shaded += sun * glint * GlintGain * (0.3 + 0.1 * forward);
			}
		}
		return shaded;
	}

	/**
	 * Opacity multiplier: drifting wisps, thinner when seen from above, faded in front of the camera.
	 * @param worldPosition Camera-relative world position.
	 */
	float Opacity(float3 worldPosition, Settings s)
	{
		const float distance = length(worldPosition);
		const float3 viewDirection = worldPosition / max(distance, 1e-3);

		const float nearFade = s.NearFade > 0.0 ? saturate((distance - 0.25 * s.NearFade) / s.NearFade) : 1.0;
		const float fromAbove = 1.0 - MaxAboveThinning * s.ThinFromAbove * saturate(-viewDirection.z);

		// World-space wisps, so they stay put on the sprites and drift slowly; height shears them
		const float3 p = (worldPosition + FrameBuffer::CameraPosAdjust.xyz) * BreakupScale;
		const float2 drift = float2(1.0, 0.6) * (SharedData::Timer * DriftSpeed);
		const float2 q = float2(p.x + 0.7 * p.z, p.y - 0.5 * p.z);
		const float noise = 0.65 * ValueNoise(q + drift) + 0.35 * ValueNoise(q * 2.7 - drift * 1.7);
		const float wisps = lerp(1.0, smoothstep(0.2, 0.75, noise), s.Breakup);

		return nearFade * fromAbove * wisps;
	}
}

#endif  // TRUE_MIST_HLSLI
