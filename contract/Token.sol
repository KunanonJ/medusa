//SPDX-License-Identifier: Unlicense
pragma solidity =0.6.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    constructor(string memory name_, string memory symbol_, uint256 totalSupply_)
        public
        ERC20(name_, symbol_)
    {
        _mint(msg.sender, totalSupply_);
    }
}