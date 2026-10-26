// True SSR: per-pixel screen-space reflections for the deferred composite.
//
// Replaces nothing on its own: it writes the reflected radiance and a confidence per pixel, and
// DeferredCompositeCS blends it over the Dynamic Cubemaps / IBL environment lookup. Where a ray
// misses, leaves the screen or the surface is too rough, confidence fades to zero and the
// cubemap shows through unchanged.

#include "Common/ColorManagement.hlsli"
#include "Common/FrameBuffer.hlsli"
#include "Common/GBuffer.hlsli"
#include "Common/Random.hlsli"
#include "Common/SharedData.hlsli"

// 24/32-bit depth: TerrainBlending ON -> R32_FLOAT, OFF -> R24_UNORM_X8_TYPELESS game depth.
#if defined(TERRAIN_BLENDING)
Texture2D<float> DepthTexture : register(t0);
#else
Texture2D<unorm float> DepthTexture : register(t0);
#endif
Texture2D<unorm float3> NormalRoughnessTexture : register(t1);
Texture2D<float3> ReflectanceTexture : register(t2);
Texture2D<float3> MainTexture : register(t3);  // lit diffuse before the composite, scene space
Texture2D<float3> SpecularTexture : register(t4);  // direct specular, linear

RWTexture2D<float4> OutputRW : register(u0);  // rgb = reflected radiance (linear), a = confidence

SamplerState LinearSampler : register(s0);

cbuffer TrueSSRCB : register(b0)
{
	uint2 OutputDim;     // dispatch size, at the output resolution
	uint ResolutionScale;  // 1 = full, 2 = half
	uint MaxSteps;
	float MaxDistance;   // world units
	float Thickness;     // world units, also scaled with distance
	float RoughnessCutoff;
	float Intensity;
	float EdgeFade;      // fraction of the screen faded at each border
	uint FrameIndex;     // 0 while TAA is off, so the jitter is static rather than glittering
	float BaseReflectance;  // F0 given to surfaces whose G-buffer reflectance is zero; 0 skips them
	float BaseRoughness;    // roughness assumed for those surfaces, whose G-buffer value is meaningless
};

static const uint RefineSteps = 4;

float3 ReconstructPosition(float2 uv, float rawDepth)
{
	float4 position = float4(2 * float2(uv.x, -uv.y + 1) - 1, rawDepth, 1);
	position = mul(FrameBuffer::CameraViewProjInverse, position);
	return position.xyz / position.w;
}

// Projects a camera-relative world position to logical screen UV and linear depth.
bool Project(float3 positionWS, out float2 uv, out float linearDepth)
{
	const float4 clip = mul(FrameBuffer::CameraViewProj, float4(positionWS, 1));
	uv = 0;
	linearDepth = 0;
	if (clip.w <= 0)
		return false;
	const float3 ndc = clip.xyz / clip.w;
	uv = ndc.xy * float2(0.5, -0.5) + 0.5;
	linearDepth = SharedData::GetScreenDepth(ndc.z);
	return all(uv >= 0) && all(uv <= 1);
}

uint2 LogicalUVToPixel(float2 uv)
{
	const float2 bufferUV = FrameBuffer::GetDynamicResolutionAdjustedScreenPosition(uv);
	return min(uint2(bufferUV * SharedData::BufferDim.xy), uint2(SharedData::BufferDim.xy) - 1);
}

float SceneLinearDepth(float2 uv)
{
	return SharedData::GetScreenDepth(DepthTexture[LogicalUVToPixel(uv)]);
}

// Positive when the ray point lies behind the visible surface, within the thickness it is a hit.
float DepthDelta(float3 positionWS, out float2 uv, out bool onScreen)
{
	float rayDepth;
	onScreen = Project(positionWS, uv, rayDepth);
	return onScreen ? rayDepth - SceneLinearDepth(uv) : -1;
}

float EdgeFactor(float2 uv)
{
	const float2 distanceToEdge = min(uv, 1 - uv);
	return saturate(min(distanceToEdge.x, distanceToEdge.y) / max(EdgeFade, 1e-4));
}

[numthreads(8, 8, 1)] void main(uint3 dispatchID : SV_DispatchThreadID) {
	if (any(dispatchID.xy >= OutputDim))
		return;

	OutputRW[dispatchID.xy] = 0;

	const uint2 pixel = dispatchID.xy * ResolutionScale;
	// Most vanilla materials (no envmap or specular) write no reflectance. Like ReShade TrueLight,
	// they can still be given a base dielectric reflectance; the composite adds their Fresnel term.
	const bool baseReflectanceOnly = all(ReflectanceTexture[pixel] <= 0);
	if (baseReflectanceOnly && BaseReflectance <= 0)
		return;

	const float rawDepth = DepthTexture[pixel];
	if (rawDepth >= 1)
		return;

	const float3 normalRoughness = NormalRoughnessTexture[pixel];
	const float roughness = baseReflectanceOnly ? BaseRoughness : 1 - normalRoughness.z;
	if (roughness >= RoughnessCutoff)
		return;

	float2 uv = (pixel + 0.5 * ResolutionScale) * SharedData::BufferDim.zw;
	uv *= FrameBuffer::DynamicResolutionParams2.xy;

	const float3 positionWS = ReconstructPosition(uv, rawDepth);
	const float3 normalVS = GBuffer::DecodeNormal(normalRoughness.xy);
	const float3 normalWS = normalize(mul(FrameBuffer::CameraViewInverse, float4(normalVS, 0)).xyz);
	const float3 V = -normalize(positionWS);
	const float3 R = reflect(-V, normalWS);

	// A ray heading back toward the camera leaves the screen through the near plane
	const float facingFade = 1 - smoothstep(0.25, 0.75, dot(R, V));
	if (facingFade <= 0)
		return;

	const float jitter = Random::InterleavedGradientNoise(float2(dispatchID.xy), FrameIndex);
	const float viewDepth = SharedData::GetScreenDepth(rawDepth);
	// Start a little off the surface so the ray does not hit the pixel it starts from
	const float3 origin = positionWS + normalWS * (0.5 + viewDepth * 0.001);

	// Quadratic step distribution: dense near the surface, where contact matters, sparse far out
	const float rcpSteps = rcp((float)max(MaxSteps, 1));
	float previousT = 0;
	float hitT = -1;
	float2 hitUV = 0;

	[loop] for (uint i = 0; i < MaxSteps; ++i)
	{
		const float s = (i + jitter) * rcpSteps;
		const float t = MaxDistance * s * s + 1.0;
		bool onScreen;
		float2 stepUV;
		const float delta = DepthDelta(origin + R * t, stepUV, onScreen);
		if (!onScreen)
			break;

		const float thickness = Thickness + t * 0.02;
		if (delta > 0 && delta < thickness) {
			// Binary refinement between the last miss and this hit
			float lo = previousT;
			float hi = t;
			hitUV = stepUV;
			[unroll] for (uint r = 0; r < RefineSteps; ++r)
			{
				const float mid = 0.5 * (lo + hi);
				bool midOnScreen;
				float2 midUV;
				const float midDelta = DepthDelta(origin + R * mid, midUV, midOnScreen);
				if (midOnScreen && midDelta > 0) {
					hi = mid;
					hitUV = midUV;
				} else {
					lo = mid;
				}
			}
			hitT = hi;
			break;
		}
		previousT = t;
	}

	if (hitT < 0)
		return;

	// Refinement can settle on a sky pixel at a silhouette, which is not a reflectable surface
	const float hitDepth = DepthTexture[LogicalUVToPixel(hitUV)];
	if (hitDepth >= 1)
		return;

	const float2 bufferUV = FrameBuffer::GetDynamicResolutionAdjustedScreenPosition(hitUV);
	const float3 radiance = ColorManagement::SceneToLinear(MainTexture.SampleLevel(LinearSampler, bufferUV, 0)) +
	                        SpecularTexture.SampleLevel(LinearSampler, bufferUV, 0);

	const float roughnessFade = 1 - smoothstep(RoughnessCutoff * 0.6, RoughnessCutoff, roughness);
	const float distanceFade = 1 - smoothstep(0.7, 1.0, hitT / MaxDistance);
	const float confidence = Intensity * EdgeFactor(hitUV) * facingFade * roughnessFade * distanceFade;

	OutputRW[dispatchID.xy] = float4(max(radiance, 0), saturate(confidence));
}
