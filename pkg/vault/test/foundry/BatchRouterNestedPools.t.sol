// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BalancerPoolToken } from "../../contracts/BalancerPoolToken.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BatchRouterNestedPools is BaseVaultTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    address internal parentPool;
    address internal childPoolA;
    address internal childPoolB;

    // Max of 5 wei of error when retrieving tokens from a nested pool.
    uint256 internal constant MAX_ROUND_ERROR = 5;

    function setUp() public override {
        BaseVaultTest.setUp();

        childPoolA = _createPool([address(usdc), address(weth)].toMemoryArray(), "childPoolA");
        childPoolB = _createPool([address(wsteth), address(dai)].toMemoryArray(), "childPoolB");
        parentPool = _createPool(
            [address(childPoolA), address(childPoolB), address(dai)].toMemoryArray(),
            "parentPool"
        );

        vm.startPrank(lp);
        uint256 childPoolABptOut = _initPool(childPoolA, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        uint256 childPoolBBptOut = _initPool(childPoolB, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);

        uint256[] memory tokenIndexes = getSortedIndexes([childPoolA, childPoolB, address(dai)].toMemoryArray());
        uint256 poolAIdx = tokenIndexes[0];
        uint256 poolBIdx = tokenIndexes[1];
        uint256 daiIdx = tokenIndexes[2];

        uint256[] memory amountsInParentPool = new uint256[](3);
        amountsInParentPool[daiIdx] = poolInitAmount;
        amountsInParentPool[poolAIdx] = childPoolABptOut;
        amountsInParentPool[poolBIdx] = childPoolBBptOut;
        vm.stopPrank();

        approveForPool(IERC20(childPoolA));
        approveForPool(IERC20(childPoolB));
        approveForPool(IERC20(parentPool));

        vm.startPrank(lp);
        _initPool(parentPool, amountsInParentPool, 0);
        vm.stopPrank();
    }

    function testRemoveLiquidityNestedPool__Fuzz(uint256 proportionToRemove) public {
        // Remove between 0.0001% and 50% of each pool liquidity.
        proportionToRemove = bound(proportionToRemove, 1e12, 50e16);

        uint256 totalPoolBPTs = BalancerPoolToken(parentPool).totalSupply();
        // Since LP is the owner of all BPT supply, and part of the BPTs were burned in the initialization step, using
        // totalSupply is more accurate to remove exactly the proportion that we intend from each pool.
        uint256 exactBptIn = totalPoolBPTs.mulDown(proportionToRemove);

        NestedPoolTestLocals memory vars = _createNestedPoolTestLocals();

        // During pool initialization, MIN_BPT amount of BPT is burned to address(0), so that the pool cannot be
        // completely drained. We need to discount this amount of tokens from the total liquidity that we can extract
        // from the child pools.
        uint256 deadTokens = (MIN_BPT / 2).mulDown(proportionToRemove);

        uint256[] memory expectedAmountsOut = new uint256[](4);
        // DAI exists in childPoolB and parentPool, so we expect 2x more DAI than the other tokens.
        // Since pools are in their initial state, we can use poolInitAmount as the balance of each token in the pool.
        // Also, we only need to account deadTokens once, since we calculate the bpts in for the parent pool using
        // totalSupply (so the burned MIN_BPT amount does not affect the bpt in calculation and the amounts out are
        // perfectly proportional to the parent pool balance)
        expectedAmountsOut[vars.daiIdx] =
            (poolInitAmount.mulDown(proportionToRemove) * 2) -
            deadTokens -
            MAX_ROUND_ERROR;
        expectedAmountsOut[vars.wethIdx] = poolInitAmount.mulDown(proportionToRemove) - deadTokens - MAX_ROUND_ERROR;
        expectedAmountsOut[vars.wstethIdx] = poolInitAmount.mulDown(proportionToRemove) - deadTokens - MAX_ROUND_ERROR;
        expectedAmountsOut[vars.usdcIdx] = poolInitAmount.mulDown(proportionToRemove) - deadTokens - MAX_ROUND_ERROR;

        vm.prank(lp);
        (address[] memory tokensOut, uint256[] memory amountsOut) = batchRouter
            .removeLiquidityProportionalFromNestedPools(parentPool, exactBptIn, expectedAmountsOut, bytes(""));

        _fillNestedPoolTestLocalsAfter(vars);
        uint256 burnedChildPoolABpts = vars.childPoolABefore.totalSupply - vars.childPoolAAfter.totalSupply;
        uint256 burnedChildPoolBBpts = vars.childPoolBBefore.totalSupply - vars.childPoolBAfter.totalSupply;

        // Check returned token array.
        assertEq(tokensOut.length, 4, "tokensOut length is wrong");
        assertEq(tokensOut[vars.daiIdx], address(dai), "DAI position on tokensOut array is wrong");
        assertEq(tokensOut[vars.wethIdx], address(weth), "WETH position on tokensOut array is wrong");
        assertEq(tokensOut[vars.wstethIdx], address(wsteth), "WstETH position on tokensOut array is wrong");
        assertEq(tokensOut[vars.usdcIdx], address(usdc), "USDC position on tokensOut array is wrong");

        // Check returned token amounts.
        assertEq(amountsOut.length, 4, "amountsOut length is wrong");
        assertApproxEqAbs(
            expectedAmountsOut[vars.daiIdx],
            amountsOut[vars.daiIdx],
            MAX_ROUND_ERROR,
            "DAI amount out is wrong"
        );
        assertApproxEqAbs(
            expectedAmountsOut[vars.wethIdx],
            amountsOut[vars.wethIdx],
            MAX_ROUND_ERROR,
            "WETH amount out is wrong"
        );
        assertApproxEqAbs(
            expectedAmountsOut[vars.wstethIdx],
            amountsOut[vars.wstethIdx],
            MAX_ROUND_ERROR,
            "WstETH amount out is wrong"
        );
        assertApproxEqAbs(
            expectedAmountsOut[vars.usdcIdx],
            amountsOut[vars.usdcIdx],
            MAX_ROUND_ERROR,
            "USDC amount out is wrong"
        );

        // Check LP Balances.
        assertEq(vars.lpAfter.dai, vars.lpBefore.dai + amountsOut[vars.daiIdx], "LP Dai Balance is wrong");
        assertEq(vars.lpAfter.weth, vars.lpBefore.weth + amountsOut[vars.wethIdx], "LP Weth Balance is wrong");
        assertEq(vars.lpAfter.wsteth, vars.lpBefore.wsteth + amountsOut[vars.wstethIdx], "LP Wsteth Balance is wrong");
        assertEq(vars.lpAfter.usdc, vars.lpBefore.usdc + amountsOut[vars.usdcIdx], "LP Usdc Balance is wrong");
        assertEq(vars.lpAfter.childPoolABpt, vars.lpBefore.childPoolABpt, "LP ChildPoolA BPT Balance is wrong");
        assertEq(vars.lpAfter.childPoolBBpt, vars.lpBefore.childPoolBBpt, "LP ChildPoolB BPT Balance is wrong");
        assertEq(
            vars.lpAfter.parentPoolBpt,
            vars.lpBefore.parentPoolBpt - exactBptIn,
            "LP ParentPool BPT Balance is wrong"
        );

        // Check Vault Balances.
        assertEq(vars.vaultAfter.dai, vars.vaultBefore.dai - amountsOut[vars.daiIdx], "Vault Dai Balance is wrong");
        assertEq(vars.vaultAfter.weth, vars.vaultBefore.weth - amountsOut[vars.wethIdx], "Vault Weth Balance is wrong");
        assertEq(
            vars.vaultAfter.wsteth,
            vars.vaultBefore.wsteth - amountsOut[vars.wstethIdx],
            "Vault Wsteth Balance is wrong"
        );
        assertEq(vars.vaultAfter.usdc, vars.vaultBefore.usdc - amountsOut[vars.usdcIdx], "Vault Usdc Balance is wrong");
        // Since all Child Pool BPTs were allocated in the parent pool, vault was holding all of them. Since part of
        // them was burned when liquidity was removed, we need to discount this amount from the vault reserves.
        assertEq(
            vars.vaultAfter.childPoolABpt,
            vars.vaultBefore.childPoolABpt - burnedChildPoolABpts,
            "Vault ChildPoolA BPT Balance is wrong"
        );
        assertEq(
            vars.vaultAfter.childPoolBBpt,
            vars.vaultBefore.childPoolBBpt - burnedChildPoolBBpts,
            "Vault ChildPoolB BPT Balance is wrong"
        );
        // Vault did not hold the parent pool BPTs.
        assertEq(
            vars.vaultAfter.parentPoolBpt,
            vars.vaultBefore.parentPoolBpt,
            "Vault ParentPool BPT Balance is wrong"
        );

        // Check ChildPoolA
        assertEq(
            vars.childPoolAAfter.weth,
            vars.childPoolABefore.weth - amountsOut[vars.wethIdx],
            "ChildPoolA Weth Balance is wrong"
        );
        assertEq(
            vars.childPoolAAfter.usdc,
            vars.childPoolABefore.usdc - amountsOut[vars.usdcIdx],
            "ChildPoolA Usdc Balance is wrong"
        );

        // Check ChildPoolB
        // Since DAI amountOut comes from parentPool and childPoolB, we need to calculate the proportion that comes
        // from childPoolB.
        assertApproxEqAbs(
            vars.childPoolBAfter.dai,
            vars.childPoolBBefore.dai - (amountsOut[vars.daiIdx] - poolInitAmount.mulDown(proportionToRemove)),
            MAX_ROUND_ERROR,
            "ChildPoolB Dai Balance is wrong"
        );
        assertEq(
            vars.childPoolBAfter.wsteth,
            vars.childPoolBBefore.wsteth - amountsOut[vars.wstethIdx],
            "ChildPoolB Wsteth Balance is wrong"
        );

        // Check ParentPool
        assertApproxEqAbs(
            vars.parentPoolAfter.dai,
            vars.parentPoolBefore.dai -
                (amountsOut[vars.daiIdx] - (poolInitAmount - (MIN_BPT / 2)).mulDown(proportionToRemove)),
            MAX_ROUND_ERROR,
            "ParentPool Dai Balance is wrong"
        );
        assertEq(
            vars.parentPoolAfter.childPoolABpt,
            vars.parentPoolBefore.childPoolABpt - burnedChildPoolABpts,
            "ParentPool ChildPoolA BPT Balance is wrong"
        );
        assertEq(
            vars.parentPoolAfter.childPoolBBpt,
            vars.parentPoolBefore.childPoolBBpt - burnedChildPoolBBpts,
            "ParentPool ChildPoolB BPT Balance is wrong"
        );
    }

    struct NestedPoolTestLocals {
        uint256 daiIdx;
        uint256 wethIdx;
        uint256 wstethIdx;
        uint256 usdcIdx;
        TokenBalances lpBefore;
        TokenBalances lpAfter;
        TokenBalances vaultBefore;
        TokenBalances vaultAfter;
        TokenBalances childPoolABefore;
        TokenBalances childPoolAAfter;
        TokenBalances childPoolBBefore;
        TokenBalances childPoolBAfter;
        TokenBalances parentPoolBefore;
        TokenBalances parentPoolAfter;
    }

    struct TokenBalances {
        uint256 dai;
        uint256 weth;
        uint256 wsteth;
        uint256 usdc;
        uint256 childPoolABpt;
        uint256 childPoolBBpt;
        uint256 parentPoolBpt;
        uint256 totalSupply;
    }

    function _createNestedPoolTestLocals() private view returns (NestedPoolTestLocals memory vars) {
        // Get output token indexes.
        uint256[] memory tokenIndexes = getSortedIndexes(
            [address(dai), address(weth), address(wsteth), address(usdc)].toMemoryArray()
        );
        vars.daiIdx = tokenIndexes[0];
        vars.wethIdx = tokenIndexes[1];
        vars.wstethIdx = tokenIndexes[2];
        vars.usdcIdx = tokenIndexes[3];

        vars.lpBefore = _getBalances(lp);
        vars.vaultBefore = _getBalances(address(vault));
        vars.childPoolABefore = _getPoolBalances(childPoolA);
        vars.childPoolBBefore = _getPoolBalances(childPoolB);
        vars.parentPoolBefore = _getPoolBalances(parentPool);
    }

    function _fillNestedPoolTestLocalsAfter(NestedPoolTestLocals memory vars) private view {
        vars.lpAfter = _getBalances(lp);
        vars.vaultAfter = _getBalances(address(vault));
        vars.childPoolAAfter = _getPoolBalances(childPoolA);
        vars.childPoolBAfter = _getPoolBalances(childPoolB);
        vars.parentPoolAfter = _getPoolBalances(parentPool);
    }

    function _getBalances(address entity) private view returns (TokenBalances memory balances) {
        balances.dai = dai.balanceOf(entity);
        balances.weth = weth.balanceOf(entity);
        balances.wsteth = wsteth.balanceOf(entity);
        balances.usdc = usdc.balanceOf(entity);
        balances.childPoolABpt = IERC20(childPoolA).balanceOf(entity);
        balances.childPoolBBpt = IERC20(childPoolB).balanceOf(entity);
        balances.parentPoolBpt = IERC20(parentPool).balanceOf(entity);
    }

    function _getPoolBalances(address pool) private view returns (TokenBalances memory balances) {
        (IERC20[] memory tokens, , uint256[] memory poolBalances, ) = vault.getPoolTokenInfo(pool);
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 currentToken = tokens[i];
            if (currentToken == dai) {
                balances.dai = poolBalances[i];
            } else if (currentToken == weth) {
                balances.weth = poolBalances[i];
            } else if (currentToken == wsteth) {
                balances.wsteth = poolBalances[i];
            } else if (currentToken == usdc) {
                balances.usdc = poolBalances[i];
            } else if (currentToken == IERC20(childPoolA)) {
                balances.childPoolABpt = poolBalances[i];
            } else if (currentToken == IERC20(childPoolB)) {
                balances.childPoolBBpt = poolBalances[i];
            }
        }

        balances.totalSupply = BalancerPoolToken(pool).totalSupply();
    }
}
