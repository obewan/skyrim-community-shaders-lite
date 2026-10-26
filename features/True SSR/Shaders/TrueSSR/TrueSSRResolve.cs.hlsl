// True SSR resolve: turns the traced reflections into what the composite reads, at full resolution.
//
// Two jobs in one pass. Glossy blur: a rough surface reflects a cone, not a ray, and the cone's
// footprint grows with the distance to what it reflects, so the blur radius follows roughness and
// hit distance, projected to pixels. Upsample: at half resolution, a plain bilinear fetch bleeds
// reflections across silhouettes; depth and normal weights keep each tap on the same surface.
// Confidence-weighted averaging lets hits fill small misses without dimming the result.

#include "Common/FrameBuffer.hlsli"
#include "Common/GBuffer.hlsli"
#include "Common/Random.hlsli"
#include "Common/SharedData.hlsli"

#if defined(TERRAIN_BLENDING)
Texture2D<float> DepthTexture : register(t0);
#else
Texture2D<unorm float> DepthTexture : register(t0);
#endif
Texture2D<unorm float3> NormalRoughnessTexture : register(t1);
Texture2D<float3> ReflectanceTexture : register(t2);
Texture2D<float4> TracedTexture : register(t3);       // trace output, at trace resolution
Texture2D<float> HitDistanceTexture : register(t4);   // trace output, at trace resolution

RWTexture2D<float4> ResolvedRW : register(u0);  // full resolution, read by the composite

cbuffer TrueSSRCB : register(b0)
{
	uint2 OutputDim;  // trace resolution
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
	uint2 FullDim;
	float BlurStrength;
	float pad0;
};

static const uint TapCount = 8;
static const float MaxBlurRadius = 16.0;  // pixels
static const float GoldenAngle = 2.39996323;

uint2 TracePixel(int2 fullPixel)
{
	return min(uint2(max(fullPixel, 0)) / ResolutionScale, OutputDim - 1);
}

[numthreads(8, 8, 1)] void main(uint3 dispatchID : SV_DispatchThreadID) {
	if (any(dispatchID.xy >= FullDim))
		return;

	const uint2 pixel = dispatchID.xy;
	ResolvedRW[pixel] = 0;

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

	const float viewDepth = SharedData::GetScreenDepth(rawDepth);
	const float3 normal = GBuffer::DecodeNormal(normalRoughness.xy);

	// Cone footprint: GGX alpha approximates the lobe's spread, scaled by the distance travelled
	// and projected to pixels at this surface's depth
	const uint2 centerTrace = TracePixel(int2(pixel));
	const float hitDistance = HitDistanceTexture[centerTrace];
	const float alpha = roughness * roughness;
	const float pixelsPerUnit = FrameBuffer::CameraProj[1][1] * 0.5 * FullDim.y / max(viewDepth, 1.0);
	float radius = BlurStrength * alpha * hitDistance * pixelsPerUnit;
	// At half resolution, always reach the neighbouring trace texels for a clean upsample
	radius = clamp(radius, ResolutionScale > 1 ? 1.5 : 0.0, MaxBlurRadius);

	const float4 center = TracedTexture[centerTrace];
	if (radius < 0.5) {
		ResolvedRW[pixel] = center;
		return;
	}

	float3 colorSum = center.rgb * center.a;
	float confidenceSum = center.a;
	float weightSum = 1.0;

	const float rotation = Random::InterleavedGradientNoise(float2(pixel), FrameIndex) * 6.2831853;
	[unroll] for (uint i = 0; i < TapCount; ++i)
	{
		const float r = sqrt((i + 0.5) / TapCount);
		const float theta = i * GoldenAngle + rotation;
		const int2 tapPixel = int2(pixel) + int2(round(float2(cos(theta), sin(theta)) * r * radius));
		if (any(tapPixel < 0) || any(tapPixel >= int2(FullDim)))
			continue;

		// Same surface only: similar depth and orientation
		const float tapDepth = SharedData::GetScreenDepth(DepthTexture[tapPixel]);
		const float depthWeight = saturate(1 - abs(tapDepth - viewDepth) / (viewDepth * 0.05));
		const float3 tapNormal = GBuffer::DecodeNormal(NormalRoughnessTexture[tapPixel].xy);
		const float normalWeight = pow(saturate(dot(tapNormal, normal)), 8);
		const float weight = exp(-2 * r * r) * depthWeight * normalWeight;
		if (weight <= 0)
			continue;

		const float4 tap = TracedTexture[TracePixel(tapPixel)];
		colorSum += tap.rgb * tap.a * weight;
		confidenceSum += tap.a * weight;
		weightSum += weight;
	}

	ResolvedRW[pixel] = float4(colorSum / max(confidenceSum, 1e-4), confidenceSum / weightSum);
}
