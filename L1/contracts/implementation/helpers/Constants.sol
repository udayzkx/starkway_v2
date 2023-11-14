// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0;

// starknet_keccak("deposit")
uint256 constant DEPOSIT_HANDLER = 352040181584456735608515580760888541466059565068553383579463728554843487745;
// starknet_keccak("deposit_with_message")
uint256 constant DEPOSIT_WITH_MESSAGE_HANDLER = 1647721306494544218056199310473443888821224259330497649032044847496103371822;
// starknet_keccak("initialize_token")
uint256 constant INIT_HANDLER = 222166934247325706163619987063261867613283618138126270722847735441241116405;

// (1 / FEE_RATE_FRACTION) is fee rate min step
uint256 constant FEE_RATE_FRACTION = 10_000;
// TODO: Remove hardcoded Starknet messaging fee when fee calculation mechanism is updated by Starkware
uint256 constant DEFAULT_STARKNET_FEE = 10**15; // 0.001 ETH

// Used in FeltUtils to validate felts
uint256 constant FIELD_PRIME = 0x800000000000011000000000000000000000000000000000000000000000001;
// Used in FeltUtils to extract Uint256 low bits from Solidity uint256
uint256 constant LOW_BITS_MASK = (2 ** 128) - 1;

// ETH Info
address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
string constant ETH_NAME = "Ethereum";
string constant ETH_SYMBOL = "ETH";
uint8 constant ETH_DECIMALS = 18;
