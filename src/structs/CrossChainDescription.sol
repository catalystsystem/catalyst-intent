// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

/// @notice The order description.
struct CrossChainDescription {
    // Destination chain identifier. For EVM use block.chainid.
    bytes32 destinationChain;
    // The minimum bond required to collect the order.
    uint256 minBond;
    // Period in seconds that the solver has to fill the order. If it is not filled within this time
    // then the order can be challanged successfully => Once claimed, the solver has block.timestamp + fillTime to fill the order.
    uint32 fillPeriod;
    // Period in seconds once after fillTime when the order can be optimistically claimed => Once claimed, the order can be challanged for until block.timestamp + fillTime + challangeTime.
    uint32 challangePeriod;
    // Period in seconds after a challange has been submitted that the solver has to verify that they filled on the destination chain.
    // It is important that solver verify that this proof period is long enough to deliver proofs before taking orders.
    uint32 proofPeriod;
    // The AMBs that can be used to deliver proofs.
    address settlementOracle; // TODO: Is there a better way to set allowed AMBS?
}

library OrderDescriptionHash {
    // Define the order description such that we can hash it.
    bytes constant CROSS_CHAIN_DESCRIPTION_TYPE =
        "CrossChainDescription(bytes32 destinationChain,uint256 minBond,uint32 fillPeriod,uint32 challangePeriod,uint32 proofPeriod,address[] approved Ambs)";

    // The hash of the order description struct identifier
    bytes32 constant CROSS_CHAIN_DESCRIPTION_TYPE_HASH = keccak256(CROSS_CHAIN_DESCRIPTION_TYPE);

    /// @notice Get the hash of the order description
    function hash(CrossChainDescription memory desc) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                CROSS_CHAIN_DESCRIPTION_TYPE_HASH,
                desc.destinationChain,
                desc.minBond,
                desc.fillPeriod,
                desc.challangePeriod,
                desc.proofPeriod,
                keccak256(abi.encode(desc)) // TODO: is supposed to be approved AMBs
            )
        );
    }
}
