// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "../interfaces/IUniswapV2Pair.sol";

contract PairMock is IUniswapV2Pair {
    function factory() external view override returns (address) {}

    function token0() external view override returns (address) {}

    function token1() external view override returns (address) {}
}
