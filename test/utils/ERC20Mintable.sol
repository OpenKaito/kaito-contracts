pragma solidity ^0.8.19;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";

contract ERC20Mintable is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
