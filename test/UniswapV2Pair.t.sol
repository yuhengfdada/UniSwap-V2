// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {UniswapV2Pair, IUniswapV2Callee} from "../src/UniswapV2Pair.sol";
import {Token} from "../src/Token.sol";

contract GoodFlashLoaner is IUniswapV2Callee {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        (address tokenAddress0, address tokenAddress1) = abi.decode(data, (address, address));
        // 这里有一个bug/feature，闪电贷的0.3% fee是根据（本金+fee）* 0.3%算的，而不是单纯的 本金*0.3%。所以实际费率应该满足(1+fee)*0.997 >= 1，也就是0.301%.
        // 普通swap则不受影响。
        if (amount0 > 0) Token(tokenAddress0).transfer(msg.sender, amount0 * 100301 / 100000);
        if (amount1 > 1) Token(tokenAddress1).transfer(msg.sender, amount1 * 100301 / 100000);
    }
}

contract BadFlashLoaner is IUniswapV2Callee {
    // tries to keep the token
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        return;
    }
}

contract TestUniswapV2Pair is Test {
    Token token1;
    Token token2;
    UniswapV2Pair pair;

    uint256 MINIMUM_LIQUIDITY = 1e3;

    event Swap(address indexed sender, uint256 amount0Out, uint256 amount1Out, address indexed to);

    function setUp() public {
        token1 = new Token("TokenX", "X", 100 ether);
        token2 = new Token("TokenY", "Y", 100 ether);
        pair = new UniswapV2Pair();
        pair.initialize(address(token1), address(token2));
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
        return _reserve1 * 997 * inputAmount / (1000 * _reserve0 + 997 * inputAmount);
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
        pair.swap(0, expectedOut, address(this), "");
        console.log(balance1Before - token1.balanceOf(address(this)));
        console.log(token2.balanceOf(address(this)) - balance2Before);
    }

    function testSwapFlashLoan() public {
        token1.transfer(address(pair), 10 ether);
        token2.transfer(address(pair), 10 ether);
        pair.mint();
        assertEq(pair.balanceOf(address(this)), 10 ether - MINIMUM_LIQUIDITY);
        assertReserves(10 ether, 10 ether);
        assertEq(pair.totalSupply(), 10 ether);

        GoodFlashLoaner gfl = new GoodFlashLoaner();
        BadFlashLoaner bfl = new BadFlashLoaner();

        token1.transfer(address(gfl), 1 ether);
        token2.transfer(address(gfl), 1 ether);

        pair.swap(1 ether, 1 ether, address(gfl), abi.encode(address(token1), address(token2)));

        assertEq(996990000000000000, token1.balanceOf(address(gfl)));
        assertEq(996990000000000000, token2.balanceOf(address(gfl)));

        vm.expectRevert("Invalid K");
        pair.swap(1 ether, 1 ether, address(bfl), abi.encode(address(token1), address(token2)));
    }
}
