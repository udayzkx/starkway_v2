// SPDX-License-Identifier: Apache-2.0.

// This application code is for illustrative purposes only
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/starkway/IStarkway.sol";

contract VaultManagerL1 {

    // Maintain immutable Starkway address
    IStarkway immutable internal starkway;

    // Maintain immutable Starkway Vault address
    address immutable internal starkwayVaultAddress;
    // Maintain Starknet Address of Vault Manager
    uint256 public vaultManagerL2Address;

    constructor(
      uint256 vaultManagerL2Address_,
      address starkwayAddress_,
      address starkwayVaultAddress_
    ) {

      starkway = IStarkway(starkwayAddress_);

      require(vaultManagerL2Address_!=0, "Error");
      vaultManagerL2Address = vaultManagerL2Address_;
      starkwayVaultAddress = starkwayVaultAddress_;
    } 

    /// @dev This is the function to be called by the user to invest a certain amount of token in a certain vault
    function investInVault(address token, uint256 amount, uint256 txFee, uint256 vaultId, uint256 userL2Address) external payable{

        // Calculate and verify if correct fee is provided
        (uint256 depositFee, uint256 starknetFee) = starkway.calculateFees(token, amount);

        require(starknetFee == msg.value, "Mismatch in starknet fees");
        require(depositFee == txFee, "Mismatch in deposit fee");
        uint256[] memory payload = new uint256[](2);
        payload[0] = vaultId;
        payload[1] = userL2Address; // This address can initiate withdrawal from L2 side, in effect acting like a custodian

        // Transfer the tokens from user to Vault Manager (this contract)
        IERC20(token).transferFrom({
          from: msg.sender,
          to: address(this),
          amount: amount + txFee
        });

        // Approve Starkway Vault to transfer tokens for deposit to L2
        IERC20(token).approve({
          spender: starkwayVaultAddress,
          amount: amount + txFee
        });

        // Finally a call is made to Starkway
        // The recipient of funds is the L2 counterpart for the Vault Manager
        // The message is also handled (received) by the L2 counterpart for the Vault Manager
        starkway.depositFundsWithMessage{value: msg.value}(
            token,
            vaultManagerL2Address,
            amount,
            txFee,
            starknetFee,
            vaultManagerL2Address,
            payload
        );
    }

    function withrawFromVault(uint256 amount, uint256 vaultId) external {

        // This issues a call to starkway to withdraw the funds
        // exact amount sent from L2 must be known apriori and be an arg to this function
        // It is not mandatory to use this function for every withdrawal
        // In particular, the vault can directly facilitate withdrawal through its own L1 address if required

    }
}