// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {UQ112x112} from "../lib/UQ112x112.sol";

import {Test, console} from "forge-std/Test.sol";

interface IUniswapV2Callee {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

contract UniswapV2Pair is ERC20 {
    address token0;
    address token1;

    // gas savings
    uint112 public reserve0;
    uint112 public reserve1;
    uint32 blockTimestampLast;

    uint256 price0CumulativeLast;
    uint256 price1CumulativeLast;

    uint256 MINIMUM_LIQUIDITY = 1e3;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1);
    event Swap(address indexed sender, uint256 amount0Out, uint256 amount1Out, address indexed to);

    constructor() ERC20("Uniswap-V2", "UNIV2", 18) {}

    function initialize(address _token0, address _token1) public {
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() public view returns (uint112, uint112) {
        return (reserve0, reserve1);
    }

    function _updateReserves(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        uint32 blockTimestamp = uint32(block.timestamp); // gas saving

        unchecked {
            // can overflow but subtraction returns the correct result.
            // e.g. 0 - 1 = INT_MAX
            uint32 timePassedSinceLast = blockTimestamp - blockTimestampLast;
            if (timePassedSinceLast > 0 && _reserve0 != 0 && _reserve1 != 0) {
                // * never overflows (224*32 <= 256); += can overflow but subtraction (performed by user) returns the correct result.
                price0CumulativeLast +=
                    uint256(UQ112x112.uqdiv(UQ112x112.encode(_reserve1), _reserve0)) * timePassedSinceLast;
                price1CumulativeLast +=
                    uint256(UQ112x112.uqdiv(UQ112x112.encode(_reserve0), _reserve1)) * timePassedSinceLast;
            }
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
    }

    // Some tokens might not give a return value for transfer() (e.g. USDT)
    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        if (!success || data.length != 0 && !abi.decode(data, (bool))) {
            revert("transfer failed");
        }
    }

    // No token amount is passed in. Users have to transfer tokens to the Pair in the same transaction.
    function mint() public returns (uint256) {
        // gas savings
        (uint112 _reserve0, uint112 _reserve1) = getReserves();

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        require(amount0 > 0 && amount1 > 0);

        uint256 liquidity;

        if (totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min(amount0 * totalSupply / _reserve0, amount1 * totalSupply / _reserve1);
        }

        _mint(msg.sender, liquidity);
        _updateReserves(balance0, balance1, _reserve0, _reserve1);

        emit Mint(msg.sender, amount0, amount1);

        return liquidity;
    }

    // No burn amount is passed in. Users have to transfer LP Token to the Pair in the same transaction.
    function burn() public returns (uint256, uint256) {
        // gas savings
        (uint112 _reserve0, uint112 _reserve1) = getReserves();

        uint256 burnAmount = balanceOf[address(this)];

        uint256 amount0 = burnAmount * _reserve0 / totalSupply;
        uint256 amount1 = burnAmount * _reserve1 / totalSupply;

        require(amount0 > 0 && amount1 > 0);

        _safeTransfer(token0, msg.sender, amount0);
        _safeTransfer(token1, msg.sender, amount1);

        _burn(address(this), burnAmount);

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        _updateReserves(balance0, balance1, _reserve0, _reserve1);

        emit Burn(msg.sender, amount0, amount1);

        return (amount0, amount1);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) public {
        require(amount0Out > 0 || amount1Out > 0, "Out amount should be greater than 0");

        // gas savings
        (uint112 _reserve0, uint112 _reserve1) = getReserves();
        require(amount0Out <= _reserve0 && amount1Out <= _reserve1, "No enough reserve");

        // optimistic transfer (for flash loans)
        if (amount0Out > 0) _safeTransfer(token0, to, amount0Out);
        if (amount1Out > 0) _safeTransfer(token1, to, amount1Out);
        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        // The user should have sent in the tokens before calling swap(), if not loaning.
        // _reserve0 - amount0Out is what's left in the balance after optimistic transfer. If balance is greater than that it means user has passed in some tokens.
        uint256 amount0In = balance0 > (_reserve0 - amount0Out) ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > (_reserve1 - amount1Out) ? balance1 - (_reserve1 - amount1Out) : 0;

        // need to cast _reserve to uint256. Otherwise easy to overflow uint112
        // the 0.3% fee is deducted on anything the user has passed in (amount0In / amount1In).
        // after fee deduction, K should be greater than the last K.
        // new K =  (balance0 - 0.003*amount0In) * (balance1 - 0.003*amount1In)
        require(
            (1000 * balance0 - 3 * amount0In) * (1000 * balance1 - 3 * amount1In)
                >= 1000 * 1000 * uint256(_reserve0) * uint256(_reserve1),
            "Invalid K"
        );

        _updateReserves(balance0, balance1, _reserve0, _reserve1);

        emit Swap(msg.sender, amount0Out, amount1Out, to);
    }
}
