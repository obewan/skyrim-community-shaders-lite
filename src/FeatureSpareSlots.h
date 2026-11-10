#pragma once

#include <array>
#include <cstdint>
#include <cstring>
#include <string_view>
#include <type_traits>

/**
 * Spare settings slots at the end of the FeatureData constant buffer (b6).
 *
 * Every shader includes `Common/SharedData.hlsli`, so adding a settings struct there changes the
 * preprocessed source of every permutation and recompiles all of them. A feature whose settings
 * live in this reserved block instead reads them from `SharedData::SpareSlots` in its own
 * `.hlsli`, so adding or changing its settings only recompiles the shaders that use the feature.
 *
 * The HLSL side is `SharedData::SpareSlots[SHARED_DATA_SPARE_SLOT_COUNT]`; keep Count in sync.
 * How to claim slots: docs/new-feature-template/NewFeatureReadme.md, "Spare settings slots".
 */
namespace FeatureSpareSlots
{
	/// Number of float4 slots reserved; must match SHARED_DATA_SPARE_SLOT_COUNT in SharedData.hlsli.
	inline constexpr uint32_t Count = 32;

	/// Bytes in one slot (one HLSL float4 register).
	inline constexpr uint32_t SlotBytes = 16;

	/// The reserved block as it is appended to the FeatureData buffer.
	struct Block
	{
		alignas(16) std::array<unsigned char, Count * SlotBytes> bytes{};
	};
	static_assert(sizeof(Block) == Count * SlotBytes);

	/// A feature's fixed slot range inside the block.
	struct Claim
	{
		std::string_view owner;
		uint32_t first;
		uint32_t count;
	};

	/**
	 * @brief Number of slots a settings struct occupies.
	 * @tparam T Settings struct mirrored in HLSL; its size must be a multiple of 16 bytes.
	 */
	template <class T>
	constexpr uint32_t SlotsFor()
	{
		static_assert(sizeof(T) % SlotBytes == 0, "Spare-slot settings must be padded to a multiple of 16 bytes");
		return static_cast<uint32_t>(sizeof(T) / SlotBytes);
	}

	/**
	 * @brief True when every claim fits in the block and no two claims overlap.
	 * @param a_claims All claims, checked at compile time with static_assert.
	 */
	template <std::size_t N>
	constexpr bool ClaimsValid(const std::array<Claim, N>& a_claims)
	{
		for (std::size_t i = 0; i < N; ++i) {
			const auto& a = a_claims[i];
			if (a.count == 0 || a.first >= Count || a.count > Count - a.first)
				return false;
			for (std::size_t j = i + 1; j < N; ++j) {
				const auto& b = a_claims[j];
				if (a.first < b.first + b.count && b.first < a.first + a.count)
					return false;
			}
		}
		return true;
	}

	/**
	 * @brief Copies a feature's settings into its claimed slots.
	 * @param a_block Block being built for this frame.
	 * @param a_first First slot of the feature's claim.
	 * @param a_data Settings struct, laid out exactly as the HLSL side unpacks it.
	 */
	template <class T>
	void Write(Block& a_block, uint32_t a_first, const T& a_data)
	{
		static_assert(std::is_trivially_copyable_v<T>, "Spare-slot settings must be trivially copyable");
		constexpr uint32_t slots = SlotsFor<T>();
		if (a_first >= Count || slots > Count - a_first)
			return;  // ClaimsValid rejects this at compile time; the guard keeps a bad call from writing out of bounds.
		std::memcpy(a_block.bytes.data() + a_first * SlotBytes, &a_data, sizeof(T));
	}
}
