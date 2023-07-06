// SPDX-License-Identifier: Apache-2.0.

// This application code is for illustrative purposes only
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FeltUtils} from "../helpers/FeltUtils.sol";
import "../interfaces/starkway/IStarkway.sol";

contract AuctionManagerL1 {

    using SafeERC20 for IERC20;

    // Maintain immutable Starkway address
    IStarkway internal immutable starkway;

    // Maintain immutable Starkway Vault address
    address internal immutable vaultAddress;

    // Maintain Starknet Address of Auction Manager
    uint256 public auctionManagerL2Address;

    // Maintain Starknet Address of knownIndexPlugin - which handles messages sent with deposit
    uint256 public knownIndexPluginAddress;

    // Every auction is gives a unique id by the Auction Manager
    uint256 public auctionId;

    // Mapping to store end time for every auction id
    mapping(uint256 => uint256) public auctionEndTime;

    // Mapping to store whether auction id is active
    mapping(uint256 => bool) public isAuctionActive;

    //Mapping to store allowed token for an auction id
    mapping(uint256 => address) public auctionToken;

    // Nested mapping to store total bid by a user(address) for a particular auction id
    mapping(address => mapping(uint256 => uint256)) public totalBidByUserInAuction;

    // List of bidders for an auction id - the first item in this list is the auction id
    mapping(uint256 => uint256[]) public auctionBidders;

    uint256 private constant LOW_BITS_MASK = (2 ** 128) - 1;

    uint256 constant DAY = 24 * 60 * 60;

    constructor(
        uint256 auctionManagerL2Address_,
        uint256 knownIndexPluginAddress_,
        address starkwayAddress_,
        address vaultAddress_
    ) {

        require(
            starkwayAddress_ != address(0),
            "Starkway Address cannot be 0"
        );

        starkway = IStarkway(starkwayAddress_);

        require(
            auctionManagerL2Address_ != 0,
            "Auction Manager Address cannot be 0"
        );

        require(
            knownIndexPluginAddress_ != 0,
            "KnownIndexPlugin Address cannot be 0"
        );

        require(
            vaultAddress_ != address(0),
            "Starkway Vault Address cannot be 0"
        );

        vaultAddress = vaultAddress_;
        auctionManagerL2Address = auctionManagerL2Address_;
        knownIndexPluginAddress = knownIndexPluginAddress_;
    }

    /// @notice This function starts an auction and returns the uint256 auctionId
    function auctionStart(address auctionToken_) public returns (uint256) {

        uint256 totalAuctions = auctionId + 1;
        auctionId = totalAuctions;

        // For simplicity every auction is assumed to last for 2 days
        auctionEndTime[totalAuctions] = block.timestamp + 2 days;
        // Set auction to active for this id
        isAuctionActive[totalAuctions] = true;

        //Set first element of bidders list as the auction id
        auctionBidders[totalAuctions].push(totalAuctions);
        auctionToken[totalAuctions] = auctionToken_;

        return totalAuctions;
    }

    /// @notice This function ends an auction specified by the auctionId
    /// and sends a message to L2 counterpart to decide the winner
    function auctionEnd(
        uint256 auctionId_,
        uint256 amount,
        uint256 txFee,
        address token,
        uint256 fundRecipient
    ) public payable {
        // check that auction can be ended
        // the amount here can be deposited by the auction organiser and deposited to an address of its chossing on L2
        require(
            isAuctionActive[auctionId_],
            "Auction not active or already ended"
        );
        require(
            auctionEndTime[auctionId_] < block.timestamp,
            "Auction end time not reached"
        );

        require(
            auctionToken[auctionId_] == token,
            "Incompatible token for auction"
        );

        // Update state for given auction id
        isAuctionActive[auctionId_] = false;

        // Transfer the tokens from user to Auction Manager (this contract)
        IERC20(token).safeTransferFrom({
            from: msg.sender,
            to: address(this),
            value: amount + txFee
        });

        // Approve Starkway Vault to transfer tokens for deposit to L2
        IERC20(token).safeApprove({
            spender: vaultAddress,
            value: amount + txFee
        });

        // Finally a call is made to Starkway
        // The recipient of funds is an address chosen by the person paying for ending the auction
        // The message is also handled (received) by the Auction Manager L2 on Starknet
        // The Auction Manager L2 then checks the final cumulative bid amount for each bidder in the bidder list and
        // stores the winning address in a storage_var on L2
        // Since we cannot create dynamic sized memory arrays
        // we need to send bidder_list directly, the first element of which is the auction id

        starkway.depositFundsWithMessage{value: msg.value}({
            token: token,
            recipientAddressL2: fundRecipient,
            deposit: amount,
            depositFee: txFee,
            starknetFee: msg.value,
            messageRecipientL2: auctionManagerL2Address,
            messagePayload: auctionBidders[auctionId_]
        });
    }

    /// @notice This function is to be called by any address interested in bidding for the auction
    /// Every bid amount is an incremental amount and added to previous bid amounts
    function increaseBid(
        uint256 auctionId_,
        uint256 amount,
        uint256 txFee,
        address token
    ) public payable {

        require(isAuctionActive[auctionId_], "Auction not active or has ended");
        require(auctionEndTime[auctionId_] >= block.timestamp, "Auction ended");
        require(amount != 0, "Cannot increase bid by 0 amount");

        require(          
            auctionToken[auctionId_] == token,
            "Incompatible token for auction"
        );
        
        uint256 currentCumulativeBid = totalBidByUserInAuction[msg.sender][
            auctionId_
        ];

        // If this is the first bid by this address, then add it to the list of bidders for this auction id
        if (currentCumulativeBid == 0) {
            auctionBidders[auctionId_].push(uint256(uint160(msg.sender)));
        }
        
        // Update total bid made by this address for this auction id
        totalBidByUserInAuction[msg.sender][auctionId_] =
            currentCumulativeBid +
            amount;

        // Construct the custom payload as per the requirements of the application
        // In this case, 1st element is the bidding address
        // 2nd element is the auction id
        // 3rd and 4th elements are the amounts (low and high 128 bits)
        // This payload has to be unpacked and interpreted by application code on L2
        uint256[] memory payload = new uint256[](4);
        payload[0] = uint160(msg.sender);
        payload[1] = auctionId_;

        (uint256 low, uint256 high) = FeltUtils.splitIntoLowHigh(
            currentCumulativeBid + amount
        );

        payload[2] = low;
        payload[3] = high;
        
        // Transfer the tokens from user to Auction Manager (this contract)
        IERC20(token).safeTransferFrom({
            from: msg.sender,
            to: address(this),
            value: amount + txFee
        });

        // Approve Starkway Vault to transfer tokens for deposit to L2
        IERC20(token).safeApprove({
            spender: vaultAddress,
            value: amount + txFee
        });

        // Finally a call is made to Starkway
        // The recipient of funds is the L2 counterpart for the Auction Manager
        // The message is also handled (received) by the KnownIndexPlugin which stores the cumulative bid amount
        // alongwith sender details etc. after unpacking and interpreting the payload
        // The interpretation depends on L1 code also
        // This payload is how the L1 counterpart communicates with the L2 counterpart

        starkway.depositFundsWithMessage{value: msg.value}({
            token: token,
            recipientAddressL2: auctionManagerL2Address,
            deposit: amount,
            depositFee: txFee,
            starknetFee: msg.value,
            messageRecipientL2: knownIndexPluginAddress,
            messagePayload: payload
        });        
    }
}
