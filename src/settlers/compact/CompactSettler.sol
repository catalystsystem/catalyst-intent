// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Ownable } from "solady/auth/Ownable.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "solady/utils/ReentrancyGuard.sol";

import { TheCompact } from "the-compact/src/TheCompact.sol";
import { IdLib } from "the-compact/src/lib/IdLib.sol";
import { EfficiencyLib } from "the-compact/src/lib/EfficiencyLib.sol";
import { BatchClaim } from "the-compact/src/types/BatchClaims.sol";
import { SplitBatchClaimComponent, SplitComponent } from "the-compact/src/types/Components.sol";

import { BaseSettler } from "../BaseSettler.sol";
import { CatalystCompactOrder, TheCompactOrderType } from "./TheCompactOrderType.sol";
import { OrderPurchase } from "../types/OrderPurchaseType.sol";
import { OutputDescription } from "../types/OutputDescriptionType.sol";

import { BytesLib } from "src/libs/BytesLib.sol";
import { OutputEncodingLib } from "src/libs/OutputEncodingLib.sol";
import { ICatalystCallback } from "src/interfaces/ICatalystCallback.sol";
import { IOracle } from "src/interfaces/IOracle.sol";

/**
 * @title Catalyst Settler supporting The Compact
 * @notice This Catalyst Settler implementation uses The Compact as the deposit scheme.
 * It is a delivery first, inputs second scheme that allows users with a deposit inside The Compact.
 *
 * Users are expected to have an existing deposit inside the Compact or purposefully deposit for the intent.
 * They then need to either register or sign a supported claim with the intent as the witness.
 * Without the deposit extension, this contract does not have a way to emit on-chain orders.
 *
 * The ownable component of the smart contract is only used for fees.
 */
contract CompactSettler is BaseSettler, Ownable {
    error NotImplemented();
    error NotOrderOwner();
    error InitiateDeadlinePassed(); // 0x606ef7f5
    error InvalidTimestampLength();
    error OrderIdMismatch(bytes32 provided, bytes32 computed);
    error FilledTooLate(uint32 expected, uint32 actual);
    error WrongChain(uint256 expected, uint256 actual); // 0x264363e1
    error GovernanceFeeTooHigh();
    error GovernanceFeeChangeNotReady();

    /**
     * @notice Governance fee will be changed shortly.
     */
    event NextGovernanceFee(uint64 nextGovernanceFee, uint64 nextGovernanceFeeTime);

    /**
     * @notice Governance fee changed. This fee is taken of the inputs.
     */
    event GovernanceFeeChanged(uint64 oldGovernanceFee, uint64 newGovernanceFee);

    TheCompact public immutable COMPACT;

    uint64 public governanceFee = 0;
    uint64 public nextGovernanceFee = 0;
    uint64 public nextGovernanceFeeTime = type(uint64).max;
    uint64 constant GOVERNANCE_FEE_CHANGE_DELAY = 7 days;
    uint256 constant GOVERNANCE_FEE_DENOM = 10 ** 18;
    uint256 constant MAX_GOVERNANCE_FEE = 10 ** 18 * 0.1; // 10%

    constructor(
        address compact,
        address initialOwner
    ) {
        COMPACT = TheCompact(compact);
        _initializeOwner(initialOwner);
    }

    // Governance Fees

    /**
     * @notice Sets a new governanceFee. Is immediately applied to orders initiated after this call.
     * @param _nextGovernanceFee New governance fee. Is bounded by MAX_GOVERNANCE_FEE.
     */
    function setGovernanceFee(
        uint64 _nextGovernanceFee
    ) external onlyOwner {
        if (_nextGovernanceFee > MAX_GOVERNANCE_FEE) revert GovernanceFeeTooHigh();
        nextGovernanceFee = _nextGovernanceFee;
        nextGovernanceFeeTime = uint64(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY;

        emit NextGovernanceFee(nextGovernanceFee, nextGovernanceFeeTime);
    }

    /**
     * @notice Applies a scheduled governace fee change.
     */
    function applyGovernanceFee() external {
        if (block.timestamp < nextGovernanceFeeTime) revert GovernanceFeeChangeNotReady();
        uint64 oldGovernanceFee = governanceFee;
        governanceFee = nextGovernanceFee;

        emit GovernanceFeeChanged(oldGovernanceFee, nextGovernanceFee);
    }

    /**
     * @notice Helper function to compute the fee.
     * @param amount To compute fee of.
     * @param fee Fee to subtract from amount. Is percentage and GOVERNANCE_FEE_DENOM based.
     * @return amountFee Fee
     */
    function _calcFee(uint256 amount, uint256 fee) internal pure returns (uint256 amountFee) {
        unchecked {
            // Check if amount * fee overflows. If it does, don't take the fee.
            if (fee == 0 || amount >= type(uint256).max / fee) return amountFee = 0;
            // The above check ensures that amount * fee < type(uint256).max.
            // amount >= amount * fee / GOVERNANCE_FEE_DENOM since fee < GOVERNANCE_FEE_DENOM
            return amountFee = amount * fee / GOVERNANCE_FEE_DENOM;
        }
    }

    function _domainNameAndVersion() internal pure virtual override returns (string memory name, string memory version) {
        name = "CatalystSettler";
        version = "Compact1";
    }

    // Generic order identifier

    function _orderIdentifier(
        CatalystCompactOrder calldata order
    ) internal view returns (bytes32) {
        return TheCompactOrderType.orderIdentifier(order);
    }

    function orderIdentifier(
        CatalystCompactOrder calldata order
    ) external view returns (bytes32) {
        return _orderIdentifier(order);
    }

    function _validateOrder(
        CatalystCompactOrder calldata order
    ) internal view {
        // Check that this is the right originChain
        if (block.chainid != order.originChainId) revert WrongChain(block.chainid, order.originChainId);
        // Check if the open deadline has been passed
        if (block.timestamp > order.fillDeadline) revert InitiateDeadlinePassed();
    }

    //--- Output Proofs ---//

    function _proofPayloadHash(bytes32 orderId, bytes32 solver, uint32 timestamp, OutputDescription calldata outputDescription) internal pure returns (bytes32 outputHash) {
        return keccak256(OutputEncodingLib.encodeFillDescription(solver, orderId, timestamp, outputDescription));
    }

    /**
     * @notice Check if a series of outputs has been proven.
     * @dev Can take a list of solvers. Should be used as a secure alternative to _validateFills
     * if someone filled one of the outputs.
     */
    function _validateFills(CatalystCompactOrder calldata order, bytes32 orderId, bytes32[] calldata solvers, uint32[] calldata timestamps) internal view {
        OutputDescription[] calldata outputDescriptions = order.outputs;

        uint256 numOutputs = outputDescriptions.length;
        uint256 numTimestamps = timestamps.length;
        if (numTimestamps != numOutputs) revert InvalidTimestampLength();

         uint32 fillDeadline = order.fillDeadline;
        bytes memory proofSeries = new bytes(32 * 4 * numOutputs);
        for (uint256 i; i < numOutputs; ++i) {
            uint32 outputFilledAt = timestamps[i];
            if (fillDeadline < outputFilledAt) revert FilledTooLate(fillDeadline, outputFilledAt);

            OutputDescription calldata output = outputDescriptions[i];
            uint256 chainId = output.chainId;
            bytes32 remoteOracle = output.remoteOracle;
            bytes32 remoteFiller = output.remoteFiller;
            bytes32 payloadHash = _proofPayloadHash(orderId, solvers[i], outputFilledAt, output);

            assembly ("memory-safe") {
                let offset := add(add(proofSeries, 0x20), mul(i, 0x80))
                mstore(offset, chainId)
                mstore(add(offset, 0x20), remoteOracle)
                mstore(add(offset, 0x40), remoteFiller)
                mstore(add(offset, 0x60), payloadHash)
            }
        }
        IOracle(order.localOracle).efficientRequireProven(proofSeries);
    }

    /**
     * @notice Check if a series of outputs has been proven.
     * @dev Notice that the solver of the first provided output is reported as the entire intent solver.
     * This function returns true if the order contains no outputs.
     * That means any order that has no outputs specified can be claimed with no issues.
     */
    function _validateFills(CatalystCompactOrder calldata order, bytes32 orderId, bytes32 solver, uint32[] calldata timestamps) internal view {
        OutputDescription[] calldata outputDescriptions = order.outputs;
        uint256 numOutputs = outputDescriptions.length;
        uint256 numTimestamps = timestamps.length;
        if (numTimestamps != numOutputs) revert InvalidTimestampLength();

         uint32 fillDeadline = order.fillDeadline;
        bytes memory proofSeries = new bytes(32 * 4 * numOutputs);
        for (uint256 i; i < numOutputs; ++i) {
            uint32 outputFilledAt = timestamps[i];
            if (fillDeadline < outputFilledAt) revert FilledTooLate(fillDeadline, outputFilledAt);

            OutputDescription calldata output = outputDescriptions[i];
            uint256 chainId = output.chainId;
            bytes32 remoteOracle = output.remoteOracle;
            bytes32 remoteFiller = output.remoteFiller;
            bytes32 payloadHash = _proofPayloadHash(orderId, solver, outputFilledAt, output);

            assembly ("memory-safe") {
                let offset := add(add(proofSeries, 0x20), mul(i, 0x80))
                mstore(offset, chainId)
                mstore(add(offset, 0x20), remoteOracle)
                mstore(add(offset, 0x40), remoteFiller)
                mstore(add(offset, 0x60), payloadHash)
            }
        }
        IOracle(order.localOracle).efficientRequireProven(proofSeries);
    }

    // --- Finalise Orders --- //

    function _validateOrderOwner(
        bytes32 orderOwner
    ) internal view {
        // We need to cast orderOwner down. This is important to ensure that
        // the solver can opt-in to an compact transfer instead of withdrawal.
        if (EfficiencyLib.asSanitizedAddress(uint256(orderOwner)) != msg.sender) revert NotOrderOwner();
    }

    function _finalise(CatalystCompactOrder calldata order, bytes calldata signatures, bytes32 orderId, bytes32 solver, bytes32 destination) internal {
        bytes calldata sponsorSignature = BytesLib.toBytes(signatures, 0);
        bytes calldata allocatorData = BytesLib.toBytes(signatures, 1);
        // Payout inputs. (This also protects against re-entry calls.)
        _resolveLock(order, sponsorSignature, allocatorData, destination);

        emit Finalised(orderId, solver, destination);
    }

    function finaliseSelf(CatalystCompactOrder calldata order, bytes calldata signatures, uint32[] calldata timestamps, bytes32 solver) external nonReentrant {
        bytes32 orderId = _orderIdentifier(order);

        bytes32 orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        _validateOrderOwner(orderOwner);

        // Deliver outputs before the order has been finalised. This requires reentrancy guards!
        _finalise(order, signatures, orderId, solver, orderOwner);

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order, orderId, solver, timestamps);

    }

    function finaliseTo(CatalystCompactOrder calldata order, bytes calldata signatures, uint32[] calldata timestamps, bytes32 solver, bytes32 destination, bytes calldata call) external nonReentrant {
        bytes32 orderId = _orderIdentifier(order);

        bytes32 orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        _validateOrderOwner(orderOwner);

        // Deliver outputs before the order has been finalised. This requires reentrancy guards!
        _finalise(order, signatures, orderId, solver, destination);
        if (call.length > 0) ICatalystCallback(EfficiencyLib.asSanitizedAddress(uint256(destination))).inputsFilled(order.inputs, call);

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order, orderId, solver, timestamps);

    }

    /**
     * @notice Finalises a cross-chain order on behalf of someone else
     * @dev This function serves to finalise intents on the origin chain. It has been assumed that assets have been
     * locked
     * inside The Compact and will be available to collect.
     * To properly collect the order details and proofs, the settler needs the solver identifier and the timestamps of
     * the fills.
     * @param order CatalystCompactOrder signed in conjunction with a Compact to form an order.
     * @param signatures A signature for the sponsor and the allocator. abi.encode(bytes(sponsorSignature),
     * bytes(allocatorData))
     */
    function finaliseFor(
        CatalystCompactOrder calldata order,
        bytes calldata signatures,
        uint32[] calldata timestamps,
        bytes32 solver,
        bytes32 destination,
        bytes calldata call,
        bytes calldata orderOwnerSignature
    ) external nonReentrant {
        bytes32 orderId = _orderIdentifier(order);

        bytes32 orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        _allowExternalClaimant(orderId, EfficiencyLib.asSanitizedAddress(uint256(orderOwner)), destination, call, orderOwnerSignature);

        // Deliver outputs before the order has been finalised. This requires reentrancy guards!
        _finalise(order, signatures, orderId, solver, destination);
        if (call.length > 0) ICatalystCallback(EfficiencyLib.asSanitizedAddress(uint256(destination))).inputsFilled(order.inputs, call);

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order, orderId, solver, timestamps);

    }

    // -- Fallback Finalise Functions -- //
    // These functions are supposed to be used whenever someone else has filled 1 of the outputs of the order.
    // It allows the proper solver to still resolve the outputs correctly.
    // It does increase the gas cost :(
    // In all cases, the solvers needs to be provided in order of the outputs in order.
    // Important, this output generally matters in regards to the orderId. The solver of the first output is determined
    // to be the "orderOwner".

    function finaliseTo(CatalystCompactOrder calldata order, bytes calldata signatures, uint32[] calldata timestamps, bytes32[] calldata solvers, bytes32 destination, bytes calldata call) external nonReentrant {
        bytes32 orderId = _orderIdentifier(order);

        bytes32 orderOwner = _purchaseGetOrderOwner(orderId, solvers[0], timestamps);
        _validateOrderOwner(orderOwner);

        // Deliver outputs before the order has been finalised. This requires reentrancy guards!
        _finalise(order, signatures, orderId, solvers[0], destination);
        if (call.length > 0) ICatalystCallback(EfficiencyLib.asSanitizedAddress(uint256(destination))).inputsFilled(order.inputs, call);

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order, orderId, solvers, timestamps);

    }

    /**
     * @notice Finalises a cross-chain order on behalf of someone else
     * @dev This function serves to finalise intents on the origin chain. It has been assumed that assets have been
     * locked inside The Compact and will be available to collect.
     * To properly collect the order details and proofs, the settler needs the solver identifier and the timestamps of
     * the fills.
     * @param order CatalystCompactOrder signed in conjunction with a Compact to form an order.
     * @param signatures A signature for the sponsor and the allocator.
     *  abi.encode(bytes(sponsorSignature), bytes(allocatorData))
     */
    function finaliseFor(
        CatalystCompactOrder calldata order,
        bytes calldata signatures,
        uint32[] calldata timestamps,
        bytes32[] calldata solvers,
        bytes32 destination,
        bytes calldata call,
        bytes calldata orderOwnerSignature
    ) external nonReentrant {
        bytes32 orderId = _orderIdentifier(order);

        bytes32 orderOwner = _purchaseGetOrderOwner(orderId, solvers[0], timestamps);
        _allowExternalClaimant(orderId, EfficiencyLib.asSanitizedAddress(uint256(orderOwner)), destination, call, orderOwnerSignature);

        // Deliver outputs before the order has been finalised. This requires reentrancy guards!
        _finalise(order, signatures, orderId, solvers[0], destination);
        if (call.length > 0) ICatalystCallback(EfficiencyLib.asSanitizedAddress(uint256(destination))).inputsFilled(order.inputs, call);

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order, orderId, solvers, timestamps);

    }

    //--- The Compact & Resource Locks ---//

    function _resolveLock(CatalystCompactOrder calldata order, bytes calldata sponsorSignature, bytes calldata allocatorData, bytes32 claimant) internal virtual {
        uint256 numInputs = order.inputs.length;
        SplitBatchClaimComponent[] memory splitBatchComponents = new SplitBatchClaimComponent[](numInputs);
        uint256[2][] calldata maxInputs = order.inputs;
        for (uint256 i; i < numInputs; ++i) {
            uint256[2] calldata input = maxInputs[i];
            uint256 tokenId = input[0];
            uint256 allocatedAmount = input[1];

            SplitComponent[] memory splitComponents;

            // If the governance fee is set, we need to add a governance fee split.
            uint64 fee = governanceFee;
            if (fee != 0) {
                uint256 governanceShare = _calcFee(allocatedAmount, fee);
                if (governanceShare != 0) {
                    unchecked {
                        // To reduce the cost associated with the governance fee, 
                        // we want to do a 6909 transfer instead of burn and mint.
                        // Note: While this function is called with replaced token, it 
                        // replaces the rightmost 20 bytes. So it takes the locktag from TokenId
                        // and places it infront of the current vault owner.
                        uint256 ownerId = IdLib.withReplacedToken(tokenId, owner());
                        splitComponents = new SplitComponent[](2);
                        // For the user
                        splitComponents[0] = SplitComponent({ claimant: uint256(claimant), amount: allocatedAmount - governanceShare });
                        // For governance
                        splitComponents[1] = SplitComponent({ claimant: uint256(ownerId), amount: governanceShare });
                        splitBatchComponents[i] = SplitBatchClaimComponent({
                            id: tokenId, // The token ID of the ERC6909 token to allocate.
                            allocatedAmount: allocatedAmount, // The original allocated amount of ERC6909 tokens.
                            portions: splitComponents
                        });
                        continue;
                    }
                }
            }
            splitComponents = new SplitComponent[](1);
            splitComponents[0] = SplitComponent({ claimant: uint256(claimant), amount: allocatedAmount });
            splitBatchComponents[i] = SplitBatchClaimComponent({
                id: tokenId, // The token ID of the ERC6909 token to allocate.
                allocatedAmount: allocatedAmount, // The original allocated amount of ERC6909 tokens.
                portions: splitComponents
            });
        }

        require(
            COMPACT.claim(
                BatchClaim({
                    allocatorData: allocatorData,
                    sponsorSignature: sponsorSignature,
                    sponsor: order.user,
                    nonce: order.nonce,
                    expires: order.expires,
                    witness: TheCompactOrderType.witnessHash(order),
                    witnessTypestring: string(TheCompactOrderType.BATCH_COMPACT_SUB_TYPES),
                    claims: splitBatchComponents
                })
            ) != bytes32(0)
        );
    }

    // --- Purchase Order --- //

    /**
     * @notice This function is called by whoever wants to buy an order from a filler.
     * If the order was purchased in time, then when the order is settled, the inputs will
     * go to the purchaser instead of the original solver.
     * @dev If you are buying a challenged order, ensure that you have sufficient time to prove the order or
     * your funds may be at risk and that you purchase it within the allocated time.
     * To purchase an order, it is required that you can produce a proper signature
     * from the solver that signs the purchase details.
     * @param orderSolvedByIdentifier Solver of the order. Is not validated, need to be correct otherwise
     * the purchase will be wasted.
     * @param expiryTimestamp Set to ensure if your transaction isn't mine quickly, you don't end
     * up purchasing an order that you cannot prove OR is not within the timeToBuy window.
     */
    function purchaseOrder(
        OrderPurchase calldata orderPurchase,
        CatalystCompactOrder calldata order,
        bytes32 orderSolvedByIdentifier,
        bytes32 purchaser,
        uint256 expiryTimestamp,
        bytes calldata solverSignature
    ) external nonReentrant {
        // Sanity check that the user thinks they are buying the right order.
        bytes32 computedOrderId = _orderIdentifier(order);
        if (computedOrderId != orderPurchase.orderId) revert OrderIdMismatch(orderPurchase.orderId, computedOrderId);

        uint256[2][] calldata inputs = order.inputs;
        _purchaseOrder(orderPurchase, inputs, orderSolvedByIdentifier, purchaser, expiryTimestamp, solverSignature);
    }
}
