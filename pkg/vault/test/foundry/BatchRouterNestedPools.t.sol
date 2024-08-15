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
        // Remove between 0.0001% and 90% of each pool liquidity.
        proportionToRemove = bound(proportionToRemove, 1e12, 90e16);

        uint256 totalPoolBPTs = BalancerPoolToken(parentPool).totalSupply();
        // Since LP is the owner of all BPT supply, and part of the BPTs were burned in the initialization step, using
        // totalSupply is more accurate to remove exactly the proportion that we intend from each pool.
        uint256 exactBptIn = totalPoolBPTs.mulDown(proportionToRemove);

        // Get output token indexes.
        uint256[] memory tokenIndexes = getSortedIndexes(
            [address(dai), address(weth), address(wsteth), address(usdc)].toMemoryArray()
        );
        uint256 daiIdx = tokenIndexes[0];
        uint256 wethIdx = tokenIndexes[1];
        uint256 wstethIdx = tokenIndexes[2];
        uint256 usdcIdx = tokenIndexes[3];

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
        expectedAmountsOut[daiIdx] = (poolInitAmount.mulDown(proportionToRemove) * 2) - deadTokens;
        expectedAmountsOut[wethIdx] = poolInitAmount.mulDown(proportionToRemove) - deadTokens;
        expectedAmountsOut[wstethIdx] = poolInitAmount.mulDown(proportionToRemove) - deadTokens;
        expectedAmountsOut[usdcIdx] = poolInitAmount.mulDown(proportionToRemove) - deadTokens;

        vm.prank(lp);
        (address[] memory tokensOut, uint256[] memory amountsOut) = batchRouter
            .removeLiquidityProportionalFromNestedPools(parentPool, exactBptIn, expectedAmountsOut, bytes(""));

        assertEq(tokensOut.length, 4, "tokensOut length is wrong");
        assertEq(tokensOut[daiIdx], address(dai), "DAI position on tokensOut array is wrong");
        assertEq(tokensOut[wethIdx], address(weth), "WETH position on tokensOut array is wrong");
        assertEq(tokensOut[wstethIdx], address(wsteth), "WstETH position on tokensOut array is wrong");
        assertEq(tokensOut[usdcIdx], address(usdc), "USDC position on tokensOut array is wrong");

        assertEq(amountsOut.length, 4, "amountsOut length is wrong");
        assertEq(expectedAmountsOut[daiIdx], amountsOut[daiIdx], "DAI amount out is wrong");
        assertEq(expectedAmountsOut[wethIdx], amountsOut[wethIdx], "WETH amount out is wrong");
        assertEq(expectedAmountsOut[wstethIdx], amountsOut[wstethIdx], "WstETH amount out is wrong");
        assertEq(expectedAmountsOut[usdcIdx], amountsOut[usdcIdx], "USDC amount out is wrong");
    }
}
