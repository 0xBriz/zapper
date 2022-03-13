// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract InputTokenMock is ERC20 {
    constructor(uint256 _initAmountToOwner)
        ERC20("InputTokenMock", "TOKENMOCK")
    {
        _mint(msg.sender, _initAmountToOwner);
    }
}
