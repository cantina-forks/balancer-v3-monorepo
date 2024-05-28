// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { PackedTokenBalance } from "./PackedTokenBalance.sol";
import { PoolConfigBits, PoolConfigLib } from "./PoolConfigLib.sol";

import {
    PoolData,
    Rounding,
    TokenType,
    PoolConfig,
    TokenConfig
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library PoolDataLib {
    using EnumerableMap for EnumerableMap.IERC20ToBytes32Map;
    using PackedTokenBalance for bytes32;

    function load(
        EnumerableMap.IERC20ToBytes32Map storage poolTokenBalances,
        PoolConfigBits poolConfig,
        mapping(IERC20 => TokenConfig) storage poolTokenConfig,
        Rounding roundingDirection
    ) internal view returns (PoolData memory poolData) {
        uint256 numTokens = poolTokenBalances.length();
        poolData.poolConfig = PoolConfigLib.toPoolConfig(poolConfig);

        poolData.tokenConfig = new TokenConfig[](numTokens);
        poolData.balancesRaw = new uint256[](numTokens);
        poolData.balancesLiveScaled18 = new uint256[](numTokens);
        poolData.decimalScalingFactors = PoolConfigLib.getDecimalScalingFactors(poolData.poolConfig, numTokens);
        poolData.tokenRates = new uint256[](numTokens);
        bytes32 packedBalance;
        IERC20 token;

        for (uint256 i = 0; i < numTokens; ++i) {
            (token, packedBalance) = poolTokenBalances.unchecked_at(i);
            poolData.tokenConfig[i] = poolTokenConfig[token];
            updateTokenRate(poolData, i);
            updateRawAndLiveBalance(poolData, i, packedBalance.getBalanceRaw(), roundingDirection);
        }
    }

    /**
     * @dev This is typically called after a reentrant callback (e.g., a "before" liquidity operation callback),
     * to refresh the poolData struct with any balances (or rates) that might have changed.
     *
     * Preconditions: tokenConfig, balancesRaw, and decimalScalingFactors must be current in `poolData`.
     * Side effects: mutates tokenRates, balancesLiveScaled18 in `poolData`.
     */
    function reloadBalancesAndRates(
        PoolData memory poolData,
        EnumerableMap.IERC20ToBytes32Map storage poolTokenBalances,
        Rounding roundingDirection
    ) internal view {
        uint256 numTokens = poolData.tokenConfig.length;

        // It's possible a reentrant hook changed the raw balances in Vault storage.
        // Update them before computing the live balances.
        bytes32 packedBalance;

        for (uint256 i = 0; i < numTokens; ++i) {
            updateTokenRate(poolData, i);

            (, packedBalance) = poolTokenBalances.unchecked_at(i);

            // Note the order dependency. This requires up-to-date tokenRate for the token at index `i` in `poolData`
            updateRawAndLiveBalance(poolData, i, packedBalance.getBalanceRaw(), roundingDirection);
        }
    }

    function updateTokenRate(PoolData memory poolData, uint256 tokenIndex) internal view {
        TokenType tokenType = poolData.tokenConfig[tokenIndex].tokenType;

        if (tokenType == TokenType.STANDARD) {
            poolData.tokenRates[tokenIndex] = FixedPoint.ONE;
        } else if (tokenType == TokenType.WITH_RATE) {
            poolData.tokenRates[tokenIndex] = poolData.tokenConfig[tokenIndex].rateProvider.getRate();
        } else {
            revert IVaultErrors.InvalidTokenConfiguration();
        }
    }

    function updateRawAndLiveBalance(
        PoolData memory poolData,
        uint256 tokenIndex,
        uint256 newRawBalance,
        Rounding roundingDirection
    ) internal pure {
        poolData.balancesRaw[tokenIndex] = newRawBalance;

        function(uint256, uint256, uint256) internal pure returns (uint256) _upOrDown = roundingDirection ==
            Rounding.ROUND_UP
            ? ScalingHelpers.toScaled18ApplyRateRoundUp
            : ScalingHelpers.toScaled18ApplyRateRoundDown;

        poolData.balancesLiveScaled18[tokenIndex] = _upOrDown(
            newRawBalance,
            poolData.decimalScalingFactors[tokenIndex],
            poolData.tokenRates[tokenIndex]
        );
    }

    function increaseTokenBalance(
        PoolData memory poolData,
        uint256 tokenIndex,
        uint256 amountToIncreaseRaw
    ) internal pure {
        updateRawAndLiveBalance(
            poolData,
            tokenIndex,
            poolData.balancesRaw[tokenIndex] + amountToIncreaseRaw,
            Rounding.ROUND_UP
        );
    }

    function decreaseTokenBalance(
        PoolData memory poolData,
        uint256 tokenIndex,
        uint256 amountToDecreaseRaw
    ) internal pure {
        updateRawAndLiveBalance(
            poolData,
            tokenIndex,
            poolData.balancesRaw[tokenIndex] - amountToDecreaseRaw,
            Rounding.ROUND_DOWN
        );
    }
}