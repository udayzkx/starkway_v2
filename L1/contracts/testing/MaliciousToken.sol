// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

enum Action {
    Normal,
    Revert,
    InfiniteLoop
}

contract MaliciousToken is IERC20, IERC20Metadata {
    //////////////
    // Settings //
    //////////////

    Action public balanceAction = Action.Normal;
    Action public nameAction = Action.Normal;
    Action public symbolAction = Action.Normal;
    Action public decimalsAction = Action.Normal;

    //////////////
    // Metadata //
    //////////////

    uint8 private _decimals;
    string private _name;
    string private _symbol;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    //////////////
    // Settings //
    //////////////

    function setBalanceActionTo(Action action) external {
      balanceAction = action;
    }

    function setNameActionTo(Action action) external {
      nameAction = action;
    }

    function setSymbolActionTo(Action action) external {
      symbolAction = action;
    }

    function setDecimalsActionTo(Action action) external {
      decimalsAction = action;
    }

    ////////////////////
    // IERC20Metadata //
    ////////////////////

    function name() external view returns (string memory) {
        Action act = nameAction;
        if (act == Action.Revert) {
            revert();
        }
        if (act == Action.InfiniteLoop) {
            return this.name();
        }
        return _name;
    }

    function symbol() external view returns (string memory) {
        Action act = symbolAction;
        if (act == Action.Revert) {
            revert();
        }
        if (act == Action.InfiniteLoop) {
            return this.symbol();
        }
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        Action act = decimalsAction;
        if (act == Action.Revert) {
            revert();
        }
        if (act == Action.InfiniteLoop) {
            return this.decimals();
        }
        return _decimals;
    }

    ////////////
    // IERC20 //
    ////////////

    function balanceOf(address user) external view returns (uint256) {
        Action act = balanceAction;
        if (act == Action.Revert) {
            revert();
        }
        if (act == Action.InfiniteLoop) {
            return this.balanceOf(user);
        }
        return 1_200 * 10**_decimals;
    }

    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }
}
