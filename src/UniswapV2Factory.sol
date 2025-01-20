// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {UniswapV2Pair} from "./UniswapV2Pair.sol";

contract UniswapV2Factory {
    mapping(address => mapping(address => address)) public pairs;

    function createPair(address _token0, address _token1) public returns (address) {
        require(_token0 != address(0) && _token1 != address(0));
        require(_token0 != _token1);
        if (_token0 > _token1) (_token1, _token0) = (_token0, _token1);

        if (pairs[_token0][_token1] != address(0)) {
            revert();
        }

        address newPair;

        bytes memory initCode = type(UniswapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_token0, _token1));
        assembly {
            newPair := create2(callvalue(), add(initCode, 32), mload(initCode), salt)
        }

        UniswapV2Pair(newPair).initialize(_token0, _token1);

        pairs[_token0][_token1] = newPair;

        return newPair;
    }
}
