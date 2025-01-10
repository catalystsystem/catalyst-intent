// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { BaseSettler } from "./BaseSettler.sol";

import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    IOriginSettler,
    ResolvedCrossChainOrder,
    Open
} from "../../interfaces/IERC7683.sol";

import { CatalystOrderType, CatalystOrderData, OutputDescription, InputDescription } from "../../libs/CatalystOrderType.sol";

import {
    ITheCompactClaims,
    BatchClaimWithWitness
} from "the-compact/src/interfaces/ITheCompactClaims.sol";

import {
    OutputEncodingLibrary
} from "../OutputEncodingLibrary.sol";

import {
    BatchClaimComponent
} from "the-compact/src/types/Components.sol";

import {
    IOracle
} from "../../interfaces/IOracle.sol";

/**
 * @title Catalyst Reactor supporting The Compact
 * @notice The Catalyst Reactor implementation with The Compact as the deposit scheme.
 * This scheme is a remote first design pattern. 
 *
 * The current design iteration of the reactor does not support ERC7683 open / OnchainCrossChainOrder.
 */
contract CatalystCompactSettler is BaseSettler {
    error NotSupported();

    ITheCompactClaims public immutable COMPACT;

    constructor(address compact) {
        COMPACT = ITheCompactClaims(compact);
    }

    //--- Output Proofs ---//

    function _proofPayloadHash(
        bytes32 orderId,
        bytes32 solver,
        uint40 timestamp,
        OutputDescription memory outputDescription
    ) pure internal returns (bytes32 outputHash) {
        return outputHash = keccak256(OutputEncodingLibrary._encodeOutputDescription(orderId, solver, timestamp, outputDescription));
    }

    /**
     * @notice Check if a series of outputs has been proven.
     * @dev Function overload for outputFilled to allow proving multiple outputs in a single call.
     * Notice that the solver of the first provided output is reported as the entire intent solver.
     */
    function _outputsFilled(address localOracle, bytes32 orderId, address solver, uint40[] memory timestamps, OutputDescription[] memory outputDescriptions) internal view {
        bytes memory proofSeries;
        
        uint256 numOutputs = outputDescriptions.length;
        for (uint256 i; i < numOutputs; ++i) {
            OutputDescription memory output = outputDescriptions[i];
            proofSeries = abi.encodePacked(
                proofSeries,
                output.remoteOracle,
                output.chainId,
                _proofPayloadHash(orderId, bytes32(uint256(uint160(solver))), timestamps[i], output)
            );
        }
        IOracle(localOracle).efficientRequireProven(proofSeries);
    }

    function maxTimestamp(uint40[] memory timestamps) external pure returns (uint256 timestamp) {
        timestamp = timestamps[0]; 

        uint256 numTimestamps = timestamps.length;
        for (uint256 i = 1; i < numTimestamps; ++i) {
            uint40 nextTimestamp = timestamps[i];
            if (timestamp < nextTimestamp) timestamp = nextTimestamp;
        }
    }

    function minTimestamp(uint40[] memory timestamps) external pure returns (uint40 timestamp) {
        timestamp = timestamps[0]; 

        uint256 numTimestamps = timestamps.length;
        for (uint256 i = 1; i < numTimestamps; ++i) {
            uint40 nextTimestamp = timestamps[i];
            if (timestamp > nextTimestamp) timestamp = nextTimestamp;
        }
    }

    function open(
        OnchainCrossChainOrder calldata /* order */
    ) external pure {
        revert NotSupported();
    }
    
    /**
     * @notice Initiates a cross-chain order
     * @dev Called by the filler. Before calling, please check if someone else has already initiated.
     * The check if an order has already been initiated is late and may use a lot of gas.
     * When a filler initiates a transaction it is important that they do the following:
     * 1. Trust the reactor. Technically, anyone can deploy a reactor that takes these interfaces.
     * As the filler has to provide collateral, this collateral could be at risk.
     * 2. Verify that the deadlines provided in the order are sane. If proof - challenge is small
     * then it may impossible to prove thus free to challenge.
     * 3. Trust the oracles. Any oracles can be provided but they may not signal that the proof
     * is or isn't valid.
     * 4. Verify all inputs & outputs. If they contain a token the filler does not trust, do not claim the order.
     * It may cause a host of problem but most importantly: Inability to payout inputs & Inability to payout collateral.
     * 5. If fillDeadline == challengeDeadline && challengerCollateralAmount == 0, then the order REQUIRES a proof
     * and the user will be set as the default challenger.
     * @param order The CrossChainOrder definition
     * @param signature Encoded lock signatures.
     */
    function openFor(GaslessCrossChainOrder calldata order, bytes calldata signature, bytes calldata originFllerData) external {
        (bytes memory sponsorSignature, bytes memory allocatorSignature) = abi.decode(signature, (bytes, bytes)); // TODO: load as calldata.
        (address solver, uint40[] memory timestamps) = abi.decode(originFllerData, (address, uint40[])); // TODO: better data structure.
        
        _validateOrder(order);

        // Decode the order data.
        (CatalystOrderData memory orderData) = abi.decode(order.orderData, (CatalystOrderData));

        bytes32 orderId = _orderIdentifier(order);

        // TODO: validate length of timestamps.
        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _outputsFilled(orderData.localOracle, orderId, solver, timestamps, orderData.outputs);

        // Payout inputs.
        _resolveLock(
            order, orderData, sponsorSignature, allocatorSignature, solver
        );

        // bytes32 identifier = orderContext.identifier;
        // if (identifier != bytes32(0)) FillerDataLib.execute(identifier, orderHash, orderKey.inputs, executionData);

        emit Open(orderId, _resolve(order, msg.sender));
    }

    //--- The Compact & Resource Locks ---//

    function _resolveLock(GaslessCrossChainOrder calldata order, CatalystOrderData memory orderData, bytes memory sponsorSignature, bytes memory allocatorSignature, address solvedBy) internal virtual {
        uint256 numInputs = orderData.inputs.length;
        BatchClaimComponent[] memory claims = new BatchClaimComponent[](numInputs);
        InputDescription[] memory maxInputs = orderData.inputs;
        for (uint256 i; i < numInputs; ++i) {
            InputDescription memory input = orderData.inputs[i];
            claims[i] = BatchClaimComponent({
                id: input.tokenId, // The token ID of the ERC6909 token to allocate.
                allocatedAmount: maxInputs[i].amount, // The original allocated amount of ERC6909 tokens.
                amount: input.amount // The claimed token amount; specified by the arbiter.
            });
        }

        bool success = COMPACT.claim(BatchClaimWithWitness({
            allocatorSignature: allocatorSignature,
            sponsorSignature: sponsorSignature,
            sponsor: order.user,
            nonce: order.nonce,
            expires: order.openDeadline,
            witness: CatalystOrderType.orderHash(order, orderData),
            witnessTypestring: string(CatalystOrderType.GASSLESS_CROSS_CHAIN_ORDER_TYPE),
            claims: claims,
            claimant: solvedBy
        }));
        require(success); // This should always be true.
    }
}
