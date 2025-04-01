// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;
pragma abicoder v2;

import { Test } from "forge-std/Test.sol";
import "../../contracts/UniswapV3Factory.sol";
import "../../contracts/UniswapV3Pool.sol";
import "../../contracts/test/OracleTest.sol";
import {IUniswapV3SwapCallback} from "../../contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IUniswapV3MintCallback} from "../../contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "openzeppelin-contracts/mocks/ERC20Mock.sol";

contract DynamicFeeIntegrationTest is Test, IUniswapV3MintCallback, IUniswapV3SwapCallback{
    ERC20Mock token0;
    ERC20Mock token1;
    UniswapV3Factory factory;
    UniswapV3Pool pool;
    OracleTest oracle;
    address user1 = address(0x123);
    address user2 = address(0x456);

    function setUp() public {
        // Deploy mock tokens
        ERC20Mock tokenA = new ERC20Mock("Token0", "TKN0", user1, 1000e18);
        ERC20Mock tokenB = new ERC20Mock("Token1", "TKN1", user1, 1000e18);

        // Deploy Uniswap V3 Factory and create a pool
        factory = new UniswapV3Factory();
        pool = UniswapV3Pool(factory.createPool(address(tokenA), address(tokenB), 500));
        pool.initialize(1000e18);

        token0 = ERC20Mock(pool.token0());
        token1 = ERC20Mock(pool.token1());

        // Deploy Oracle Mock to manipulate TWAP
        oracle = new OracleTest();

        // Mint and approve tokens for swapping
        token0.mint(address(this), 1_000_000e40);
        token1.mint(address(this), 1_000_000e40);

        pool.toggleDynamicFees(); // Enable dynamic fees
    }

    function test_DynamicFee_Changes_Low_Volatility() public {
        bool zeroForOne = token0 > token1;

        // Initial swap - price change < 0.5%, should apply 0.05% fee
        pool.mint(user1, getMinTick(60), getMaxTick(60), 5000000000e18, abi.encode(""));

        pool.increaseObservationCardinalityNext(10);
        vm.warp(block.timestamp + 1000);
        vm.roll(block.number + 1); 

        pool.swap(user1, zeroForOne, 1e18, (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1),
                abi.encode(""));
        
        // Get the fee after low volatility swap
        (, int24 currentTick, , , , , ) = pool.slot0();
        uint24 fee = pool.getFee(currentTick);
        require(fee == uint24(500), "Fee should be 0.05% for low volatility");
    }

    function test_DynamicFee_Changes_With_Medium_Volatility() public {
        bool zeroForOne = token0 > token1;

        // Initial swap - 0.5% < price change < 1.5%, should apply 0.3% fee
        pool.mint(user1, getMinTick(60), getMaxTick(60), 2000000000e18, abi.encode(""));

        pool.increaseObservationCardinalityNext(10);
        vm.warp(block.timestamp + 1000);
        vm.roll(block.number + 1); 

        pool.swap(user1, zeroForOne, 1e18, (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1),
                abi.encode(""));
        
        // Get the fee after medium volatility swap
        (, int24 currentTick, , , , , ) = pool.slot0();
        uint24 fee = pool.getFee(currentTick);
        require(fee == uint24(3000), "Fee should be 0.3% for medium volatility");
    }

    function test_DynamicFee_Changes_With_High_Volatility() public {
        bool zeroForOne = token0 > token1;

        // Initial swap - price change >= 1.5%, should apply 1% fee
        pool.mint(user1, getMinTick(60), getMaxTick(60), 5000000000e18, abi.encode(""));

        pool.increaseObservationCardinalityNext(10);
        vm.warp(block.timestamp + 1000);
        vm.roll(block.number + 1); 

        // Simulate a large price movement with another swap
        pool.swap(
            user2, zeroForOne, 50_000e18, 
            (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1),
            abi.encode("")
        );

        // Get the fee after high volatility swap
       (,int24 currentTick, , , , , ) = pool.slot0();
        uint24 fee = pool.getFee(currentTick);
        require(fee == uint24(10_000), "Fee should be 1% for high volatility");
    }

    function test_fees_without_dynamic_swap_fee() public {
        pool.toggleDynamicFees(); // disable dynamic fees
        bool zeroForOne = token0 < token1;

        pool.mint(user1, getMinTick(60), getMaxTick(60), 2e18, abi.encode(""));

        pool.increaseObservationCardinalityNext(10);
        vm.warp(block.timestamp + 1000);
        vm.roll(block.number + 1); 

        pool.swap(user1, zeroForOne, 100e18, (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1),
                abi.encode(""));
        
        (, int24 currentTick, , , , , ) = pool.slot0();
        uint24 feeLow = pool.getFee(currentTick);
        require(feeLow == pool.fee(), "Fee should be default for low volatility");

        pool.mint(user2, getMinTick(60), getMaxTick(60), 2e18, abi.encode(""));
        pool.swap(
            user2, zeroForOne, 50_000e18, 
            (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1),
            abi.encode("")
        );

       (,currentTick, , , , , ) = pool.slot0();
        uint24 feeHigh = pool.getFee(currentTick);
        require(feeHigh == pool.fee(), "Fee should default for high volatility");
    }

    function getMinTick(int24 tickSpacing) public pure returns (int24) {
        return (int24(-887272) / tickSpacing) * tickSpacing;
    }

    function getMaxTick(int24 tickSpacing) public pure returns (int24) {
        return (int24(887272) / tickSpacing) * tickSpacing;
    }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override {
        if (amount0Owed > 0) token0.transfer(address(pool), amount0Owed);
        if (amount1Owed > 0) token1.transfer(address(pool), amount1Owed);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        if (amount0Delta > 0) token0.transfer(address(pool), uint256(amount0Delta));
        if (amount1Delta > 0) token1.transfer(address(pool), uint256(amount1Delta));
    }
}