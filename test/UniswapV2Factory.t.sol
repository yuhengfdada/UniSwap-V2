// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {UniswapV2Pair} from "../src/UniswapV2Pair.sol";
import {UniswapV2Factory} from "../src/UniswapV2Factory.sol";
import {Token} from "../src/Token.sol";

contract TestUniswapV2Pair is Test {
    Token token0;
    Token token1;
    UniswapV2Factory factory;

    function setUp() public {
        token0 = new Token("TokenX", "X", 100 ether);
        token1 = new Token("TokenY", "Y", 100 ether);
        factory = new UniswapV2Factory();
    }

    function getAddress(address addr, bytes memory bytecode, uint256 salt) public pure returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), addr, salt, keccak256(bytecode)));

        // NOTE: cast last 20 bytes of hash to address
        return address(uint160(uint256(hash)));
    }

    function testCreatePair() public {
        address _token0 = address(token0);
        address _token1 = address(token1);

        if (_token0 > _token1) (_token1, _token0) = (_token0, _token1);
        bytes memory initCode = type(UniswapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_token0, _token1));
        address expected = getAddress(address(factory), initCode, uint256(salt));
        address actual = factory.createPair(_token0, _token1);
        assertEq(expected, actual);
    }
}
