// SPDX-License-Identifier: Apache-2.0.

// This application code is for illustrative purposes only

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/starkway/IStarkway.sol";

contract YieldManagerL1 {

    using SafeERC20 for IERC20;

    // Maintain immutable Starkway address
    IStarkway internal immutable starkway;

    // Maintain immutable Starkway Vault address
    address internal immutable starkwayVaultAddress;

    // Maintain Starknet Address of Yield Manager
    uint256 public yieldManagerL2Address;

    // Maintain Starknet Address of historicalDataPlugin - which handles messages sent with deposit
    uint256 public historicalDataPluginAddress;

    // Mapping to store allowed token for a particular vault id
    mapping(uint256 => address) public vaultToToken;

    address public immutable owner;

    constructor(
        uint256 yieldManagerL2Address_,
        uint256 historicalDataPluginAddress_,
        address starkwayAddress_,
        address starkwayVaultAddress_
    ) {

        require(
            starkwayAddress_ != address(0), 
            "Starkway Address cannot be 0");

        starkway = IStarkway(starkwayAddress_);

        require(
            yieldManagerL2Address_ != 0,
            "Auction Manager Address cannot be 0"
        );

        require(
            historicalDataPluginAddress_ != 0,
            "KnownIndexPlugin Address cannot be 0"
        );

        starkwayVaultAddress = starkwayVaultAddress_;
        yieldManagerL2Address = yieldManagerL2Address_;
        historicalDataPluginAddress = historicalDataPluginAddress_;
        owner = msg.sender;
    }

    /// @dev  Function to be called by whoever wants to invest a certain amount of tokens for earning yield on L2
    function investForYield(
        address token, 
        uint256 amount, 
        uint256 txFee, 
        uint256 vaultId, 
        uint256 userL2Address) external payable{

        // Calculate and verify if correct fee is provided
        (uint256 depositFee, uint256 starknetFee) = starkway.calculateFees(token, amount);

        require(starknetFee == msg.value, "Mismatch in starknet fees");
        require(depositFee == txFee, "Mismatch in deposit fee");

        // Check if token is compatible with the vault id
        require(vaultToToken[vaultId] == token, "Incompatible token for vault");
        
        // Prepare application specific payload
        // L2 side needs to know format of this payload for interpretation
        uint256[] memory payload = new uint256[](3);
        payload[0] = yieldManagerL2Address;
        payload[1] = vaultId;
        payload[2] = userL2Address; // This address can initiate withdrawal from L2 side, in effect acting like a custodian

        // Transfer the tokens from user to Yield Manager (this contract)
        IERC20(token).safeTransferFrom({
          from: msg.sender,
          to: address(this),
          value: amount + txFee
        });

        // Approve Starkway Vault to transfer tokens for deposit to L2
        IERC20(token).safeApprove({
          spender: starkwayVaultAddress,
          value: amount + txFee
        });

        // Finally a call is made to Starkway
        // The recipient of funds is the L2 counterpart for the Yield Manager
        // The message is handled (received) by the Historical Data Plugin
        starkway.depositFundsWithMessage{value: msg.value}(
            token,
            yieldManagerL2Address,
            amount,
            txFee,
            starknetFee,
            historicalDataPluginAddress,
            payload
        );
    }

    // function to store allowed token corresponding to a vault id
    function setTokenForVault(uint256 vaultId, address tokenAddress) external {

        require(msg.sender == owner, "Callable only by owner");

        vaultToToken[vaultId] = tokenAddress;
    }

    // Function to complete withdrawal on L1 side is not shown since it is not part of the message attribution framework

}