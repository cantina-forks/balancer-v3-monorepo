// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";

import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";

import { RateProviderMock } from "../../../contracts/test/RateProviderMock.sol";
import { VaultMock } from "../../../contracts/test/VaultMock.sol";
import { VaultExtensionMock } from "../../../contracts/test/VaultExtensionMock.sol";
import { Router } from "../../../contracts/Router.sol";
import { BatchRouter } from "../../../contracts/BatchRouter.sol";
import { VaultStorage } from "../../../contracts/VaultStorage.sol";
import { RouterMock } from "../../../contracts/test/RouterMock.sol";
import { PoolMock } from "../../../contracts/test/PoolMock.sol";

import { VaultMockDeployer } from "./VaultMockDeployer.sol";

abstract contract BaseVaultTest is VaultStorage, BaseTest {
    using ArrayHelpers for *;

    struct Balances {
        uint256[] userTokens;
        uint256 userBpt;
        uint256[] poolTokens;
    }

    uint256 constant MIN_BPT = 1e6;

    bytes32 constant ZERO_BYTES32 = 0x0000000000000000000000000000000000000000000000000000000000000000;
    bytes32 constant ONE_BYTES32 = 0x0000000000000000000000000000000000000000000000000000000000000001;

    // Vault mock.
    IVaultMock internal vault;
    // Vault extension mock.
    VaultExtensionMock internal vaultExtension;
    // Router mock.
    RouterMock internal router;
    // Batch router
    BatchRouter internal batchRouter;
    // Authorizer mock.
    BasicAuthorizerMock internal authorizer;
    // Pool for tests.
    address internal pool;
    // Rate provider mock.
    RateProviderMock internal rateProvider;

    // Default amount to use in tests for user operations.
    uint256 internal defaultAmount = 1e3 * 1e18;
    // Default amount round up.
    uint256 internal defaultAmountRoundUp = defaultAmount + 1;
    // Default amount round down.
    uint256 internal defaultAmountRoundDown = defaultAmount - 1;
    // Default amount of BPT to use in tests for user operations.
    uint256 internal bptAmount = 2e3 * 1e18;
    // Default amount of BPT round down.
    uint256 internal bptAmountRoundDown = bptAmount - 1;
    // Amount to use to init the mock pool.
    uint256 internal poolInitAmount = 1e3 * 1e18;
    // Default rate for the rate provider mock.
    uint256 internal mockRate = 2e18;
    // Default swap fee percentage.
    uint256 internal swapFeePercentage = 0.01e18; // 1%
    // Default protocol swap fee percentage.
    uint64 internal protocolSwapFeePercentage = 0.50e18; // 50%

    function setUp() public virtual override {
        BaseTest.setUp();

        vault = IVaultMock(address(VaultMockDeployer.deploy()));
        vm.label(address(vault), "vault");
        authorizer = BasicAuthorizerMock(address(vault.getAuthorizer()));
        vm.label(address(authorizer), "authorizer");
        router = new RouterMock(IVault(address(vault)), weth);
        vm.label(address(router), "router");
        batchRouter = new BatchRouter(IVault(address(vault)), weth);
        vm.label(address(batchRouter), "batch router");
        pool = createPool();

        // Approve vault allowances
        approveVault(admin);
        approveVault(lp);
        approveVault(alice);
        approveVault(bob);
        approveVault(broke);

        // Add initial liquidity
        initPool();
    }

    function approveVault(address user) internal {
        vm.startPrank(user);

        for (uint256 index = 0; index < tokens.length; index++) {
            tokens[index].approve(address(vault), type(uint256).max);
        }

        vm.stopPrank();
    }

    function initPool() internal virtual {
        vm.startPrank(lp);
        _initPool(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();
    }

    function _initPool(
        address poolToInit,
        uint256[] memory amountsIn,
        uint256 minBptOut
    ) internal virtual returns (uint256 bptOut) {
        (IERC20[] memory tokens, , , , ) = vault.getPoolTokenInfo(poolToInit);
        return router.initialize(poolToInit, tokens, amountsIn, minBptOut, false, "");
    }

    function createPool() internal virtual returns (address) {
        return _createPool([address(dai), address(usdc)].toMemoryArray(), "pool");
    }

    function _createPool(address[] memory tokens, string memory label) internal virtual returns (address) {
        PoolMock newPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 Pool",
            "ERC20POOL",
            vault.buildTokenConfig(tokens.asIERC20()),
            true,
            365 days,
            address(0)
        );
        vm.label(address(newPool), label);
        return address(newPool);
    }

    function setSwapFeePercentage(uint256 percentage) internal {
        _setSwapFeePercentage(pool, percentage);
    }

    function _setSwapFeePercentage(address setPool, uint256 percentage) internal {
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), admin);
        vm.prank(admin);
        vault.setStaticSwapFeePercentage(setPool, percentage);
    }

    function setProtocolSwapFeePercentage(uint64 percentage) internal {
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setProtocolSwapFeePercentage.selector), admin);
        vm.prank(admin);
        vault.setProtocolSwapFeePercentage(percentage);
    }

    function getBalances(address user) internal view returns (Balances memory balances) {
        balances.userBpt = IERC20(pool).balanceOf(user);

        (IERC20[] memory tokens, , uint256[] memory poolBalances, , ) = vault.getPoolTokenInfo(pool);
        balances.poolTokens = poolBalances;
        balances.userTokens = new uint256[](poolBalances.length);
        for (uint256 i = 0; i < poolBalances.length; i++) {
            // Don't assume token ordering.
            balances.userTokens[i] = tokens[i].balanceOf(user);
        }
    }

    function getSalt(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }
}
