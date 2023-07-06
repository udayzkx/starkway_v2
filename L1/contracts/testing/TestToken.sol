// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {

    uint8 private _decimals;
    
    constructor(
        string memory name_, 
        string memory symbol_, 
        uint8 decimals_
    ) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    /**
     * @dev function to mint tokens
     * @param to The address to mint tokens to.
     * @param amount The amount of tokens to be minted
     **/
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    /**
     * @dev Function which returns the decimals of the ERC20 token
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
