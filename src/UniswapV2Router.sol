// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {UniswapV2Pair} from "./UniswapV2Pair.sol";
import {UniswapV2Factory} from "./UniswapV2Factory.sol";

contract UniswapV2Router {
    UniswapV2Factory factory;

    constructor(address _factory) {
        factory = UniswapV2Factory(_factory);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) public returns (uint256 amountA, uint256 amountB, uint256 amountLiquidity) {
        (amountA, amountB) = _calculateLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);

        address pairAddr = _pairOf(tokenA, tokenB);
        require(pairAddr != address(0));
        UniswapV2Pair pair = UniswapV2Pair(pairAddr);

        _safeTransferFrom(tokenA, msg.sender, pairAddr, amountA);
        _safeTransferFrom(tokenB, msg.sender, pairAddr, amountB);
        amountLiquidity = pair.mint();
    }

    function removeLiquidity(address tokenA, address tokenB, uint256 liquidity, uint256 amountAMin, uint256 amountBMin)
        public
        returns (uint256 amountA, uint256 amountB)
    {
        address pairAddr = _pairOf(tokenA, tokenB);
        require(pairAddr != address(0));
        UniswapV2Pair pair = UniswapV2Pair(pairAddr);

        pair.transferFrom(msg.sender, pairAddr, liquidity);
        (amountA, amountB) = pair.burn();
        require(amountA >= amountAMin && amountB >= amountBMin);
    }

    // TODO
    // function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to)
    //     public
    //     returns (uint256[] memory amounts)
    // {
    //     amounts = _getAmounts(amountIn, path);
    //     if (amounts[amounts.length - 1] < amountOutMin) {
    //         revert("swapExactTokensForTokens: insufficient output");
    //     }
    // }

    function _getAmount(uint256 _inputAmount, uint256 _inputReserve, uint256 _outputReserve)
        private
        pure
        returns (uint256)
    {
        require(_inputReserve >= 0 && _outputReserve >= 0);
        // We deduct 0.3% fee from _inputAmount.
        // Note that Solidity doesn't support floating-point calculation so the formula has to be tweaked a bit.
        return (_inputAmount * 997 * _outputReserve) / (_inputReserve * 1000 + _inputAmount * 997);
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) public {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, amount));
        if (!success || data.length != 0 && !abi.decode(data, (bool))) {
            revert("safeTransferFrom: failure");
        }
    }

    function _pairOf(address tokenA, address tokenB) public view returns (address) {
        (tokenA, tokenB) = _sortPairs(tokenA, tokenB);
        return factory.pairs(tokenA, tokenB);
    }

    function _sortPairs(address tokenA, address tokenB) public pure returns (address, address) {
        if (tokenA > tokenB) return (tokenB, tokenA);
        return (tokenA, tokenB);
    }

    function _getReserves(address tokenA, address tokenB) public view returns (uint256, uint256) {
        address pairAddr = _pairOf(tokenA, tokenB);
        require(pairAddr != address(0));
        UniswapV2Pair pair = UniswapV2Pair(pairAddr);
        return pair.getReserves();
    }

    function _quote(uint256 reserveA, uint256 reserveB, uint256 amountA) public pure returns (uint256) {
        return reserveB * amountA / reserveA;
    }

    function _calculateLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) public view returns (uint256 amountA, uint256 amountB) {
        (uint256 reserveA, uint256 reserveB) = _getReserves(tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = _quote(reserveA, reserveB, amountADesired);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "Insufficient B output");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = _quote(reserveB, reserveA, amountBDesired);
                require(amountAOptimal >= amountAMin, "Insufficient A output");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
}
