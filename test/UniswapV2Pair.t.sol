// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {UniswapV2Pair} from "../src/UniswapV2Pair.sol";
import {Token} from "../src/Token.sol";

contract TestUniswapV2Pair is Test {
    Token token1;
    Token token2;
    UniswapV2Pair pair;

    uint256 MINIMUM_LIQUIDITY = 1e3;

    event Swap(address indexed sender, uint256 amount0Out, uint256 amount1Out, address indexed to);

    function setUp() public {
        token1 = new Token("TokenX", "X", 100 ether);
        token2 = new Token("TokenY", "Y", 100 ether);
        pair = new UniswapV2Pair(address(token1), address(token2));
    }

    function assertReserves(uint256 token0Reserve, uint256 token1Reserve) public view {
        assertEq(token0Reserve, pair.reserve0());
        assertEq(token1Reserve, pair.reserve1());
    }

    function testMint() public {
        token1.transfer(address(pair), 10 ether);
        token2.transfer(address(pair), 10 ether);
        pair.mint();
        assertEq(pair.balanceOf(address(this)), 10 ether - MINIMUM_LIQUIDITY);
        assertReserves(10 ether, 10 ether);
        assertEq(pair.totalSupply(), 10 ether);
    }

    function testMintUnbalanced() public {
        token1.transfer(address(pair), 1 ether);
        token2.transfer(address(pair), 1 ether);
        pair.mint();
        assertEq(pair.balanceOf(address(this)), 1 ether - MINIMUM_LIQUIDITY);
        assertEq(pair.totalSupply(), 1 ether);

        token1.transfer(address(pair), 2 ether);
        token2.transfer(address(pair), 1 ether);
        pair.mint();
        assertEq(pair.balanceOf(address(this)), 2 ether - MINIMUM_LIQUIDITY);
        assertReserves(3 ether, 2 ether);
        assertEq(pair.totalSupply(), 2 ether);
    }

    function testBurn() public {
        token1.transfer(address(pair), 10 ether);
        token2.transfer(address(pair), 10 ether);
        pair.mint();
        assertEq(pair.balanceOf(address(this)), 10 ether - MINIMUM_LIQUIDITY);
        assertReserves(10 ether, 10 ether);
        assertEq(pair.totalSupply(), 10 ether);

        pair.transfer(address(pair), 5 ether);
        pair.burn();
        assertEq(pair.balanceOf(address(this)), 5 ether - MINIMUM_LIQUIDITY);
        assertReserves(5 ether, 5 ether);
        assertEq(token1.balanceOf(address(this)), 95 ether);
        assertEq(token2.balanceOf(address(this)), 95 ether);
        assertEq(pair.totalSupply(), 5 ether);
    }

    function _calcExpectedOut(uint112 reserve0, uint112 reserve1, uint256 inputAmount) private pure returns (uint256) {
        uint256 _reserve0 = uint256(reserve0);
        uint256 _reserve1 = uint256(reserve1);
        return _reserve1 * inputAmount / (_reserve0 + inputAmount);
    }

    function testSwap() public {
        token1.transfer(address(pair), 10 ether);
        token2.transfer(address(pair), 10 ether);
        pair.mint();
        assertEq(pair.balanceOf(address(this)), 10 ether - MINIMUM_LIQUIDITY);
        assertReserves(10 ether, 10 ether);
        assertEq(pair.totalSupply(), 10 ether);

        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 balance2Before = token2.balanceOf(address(this));

        (uint112 _reserve0, uint112 _reserve1) = pair.getReserves();

        uint256 expectedOut = _calcExpectedOut(_reserve0, _reserve1, 1 ether);

        token1.transfer(address(pair), 1 ether);
        vm.expectEmit(true, true, false, true, address(pair));
        emit Swap(address(this), 0, expectedOut, address(this));
        pair.swap(0, expectedOut, address(this));
        console.log(balance1Before - token1.balanceOf(address(this)));
        console.log(token2.balanceOf(address(this)) - balance2Before);
    }
}
