// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    AddLiquidityKind,
    PoolHooks,
    RemoveLiquidityKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";

abstract contract BaseHook is IPoolHooks {
    IVault public immutable vault;
    address public immutable supportedFactory;

    constructor(IVault _vault, address _supportedFactory) {
        vault = _vault;
        supportedFactory = _supportedFactory;
    }

    function isSupportedFactory(address factory) public view returns (bool) {
        if (supportedFactory == address(0) || supportedFactory == factory) {
            return true;
        }

        return false;
    }

    /**
     * @notice Returns the available hooks.
     * @dev This function should be overridden by derived contracts to return the hooks they support.
     * @return PoolHooks
     */
    function availableHooks() external pure virtual returns (PoolHooks memory);

    /// @inheritdoc IPoolHooks
    function onBeforeInitialize(
        uint256[] memory exactAmountsIn,
        bytes memory userData
    ) external returns (bool) {
        return _onBeforeInitialize(msg.sender, exactAmountsIn, userData);
    }

    /// @inheritdoc IPoolHooks
    function onAfterInitialize(
        uint256[] memory exactAmountsIn,
        uint256 bptAmountOut,
        bytes memory userData
    ) external returns (bool) {
        return _onAfterInitialize(msg.sender, exactAmountsIn, bptAmountOut, userData);
    }

    /// @inheritdoc IPoolHooks
    function onBeforeAddLiquidity(
        address sender,
        AddLiquidityKind kind,
        uint256[] memory maxAmountsInScaled18,
        uint256 minBptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (bool success) {
        return _onBeforeAddLiquidity(msg.sender, sender, kind, maxAmountsInScaled18, minBptAmountOut, balancesScaled18, userData);
    }

    /// @inheritdoc IPoolHooks
    function onAfterAddLiquidity(
        address sender,
        uint256[] memory amountsInScaled18,
        uint256 bptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (bool success) {
        return _onAfterAddLiquidity(msg.sender, sender, amountsInScaled18, bptAmountOut, balancesScaled18, userData);
    }

    /// @inheritdoc IPoolHooks
    function onBeforeRemoveLiquidity(
        address sender,
        RemoveLiquidityKind kind,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOutScaled18,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (bool success) {
        return _onBeforeRemoveLiquidity(
            msg.sender,
            sender,
            kind,
            maxBptAmountIn,
            minAmountsOutScaled18,
            balancesScaled18,
            userData
        );
    }

    /// @inheritdoc IPoolHooks
    function onAfterRemoveLiquidity(
        address sender,
        uint256 bptAmountIn,
        uint256[] memory amountsOutScaled18,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (bool success) {
        return _onAfterRemoveLiquidity(
            msg.sender,
            sender,
            bptAmountIn,
            amountsOutScaled18,
            balancesScaled18,
            userData
        );
    }

    /// @inheritdoc IPoolHooks
    function onBeforeSwap(IBasePool.PoolSwapParams memory params) external returns (bool success) {
        return _onBeforeSwap(msg.sender, params);
    }

    /// @inheritdoc IPoolHooks
    function onAfterSwap(
        IPoolHooks.AfterSwapParams memory params,
        uint256 amountCalculatedScaled18
    ) external returns (bool success) {
        return _onAfterSwap(msg.sender, params, amountCalculatedScaled18);
    }

    /*******************************************************************************************************
            Default function implementations.
            Derived contracts should overwrite the corresponding functions for their supported hooks.
    *******************************************************************************************************/

    function _onBeforeInitialize(
        address, // pool
        uint256[] memory, // exactAmountsIn
        bytes memory // userData
    ) internal virtual returns (bool) {
        return false;
    }

    function _onAfterInitialize(
        address, // pool
        uint256[] memory, // exactAmountsIn
        uint256, // bptAmountOut
        bytes memory // userData
    ) internal virtual returns (bool) {
        return false;
    }

    function _onBeforeAddLiquidity(
        address, // pool
        address, // sender
        AddLiquidityKind, // kind
        uint256[] memory, // maxAmountsInScaled18
        uint256, // minBptAmountOut
        uint256[] memory, // balancesScaled18
        bytes memory // userData
    ) internal virtual returns (bool) {
        return false;
    }

    function _onAfterAddLiquidity(
        address, // pool
        address, // sender
        uint256[] memory, // amountsInScaled18
        uint256, // bptAmountOut
        uint256[] memory, // balancesScaled18
        bytes memory // userData
    ) internal virtual returns (bool) {
        return false;
    }

    function _onBeforeRemoveLiquidity(
        address, // pool
        address, // sender
        RemoveLiquidityKind, // kind
        uint256, // maxBptAmountIn
        uint256[] memory, // minAmountsOutScaled18
        uint256[] memory, // balancesScaled18
        bytes memory // userData
    ) internal virtual returns (bool) {
        return false;
    }

    function _onAfterRemoveLiquidity(
        address, // pool
        address, // sender
        uint256, // bptAmountIn
        uint256[] memory, // amountsOutScaled18
        uint256[] memory, // balancesScaled18
        bytes memory // userData
    ) internal virtual returns (bool) {
        return false;
    }

    function _onBeforeSwap(
        address, // pool
        IBasePool.PoolSwapParams memory // params
    ) internal virtual returns (bool) {
        return false;
    }

    function _onAfterSwap(
        address, // pool
        IPoolHooks.AfterSwapParams memory, // params
        uint256 // amountCalculatedScaled18
    ) internal virtual returns (bool) {
        return false;
    }
}
