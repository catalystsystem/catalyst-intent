// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Endian } from "bitcoinprism-evm/src/Endian.sol";
import { IBtcPrism } from "bitcoinprism-evm/src/interfaces/IBtcPrism.sol";
import { NoBlock, TooFewConfirmations } from "bitcoinprism-evm/src/interfaces/IBtcTxVerifier.sol";
import { BtcProof, BtcTxProof, ScriptMismatch } from "bitcoinprism-evm/src/library/BtcProof.sol";
import { AddressType, BitcoinAddress, BtcScript } from "bitcoinprism-evm/src/library/BtcScript.sol";

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { OutputDescription } from "../../reactors/CatalystOrderType.sol";
import { CatalystCompactFilledOrder, TheCompactOrderType } from "../../reactors/settler/compact/TheCompactOrderType.sol";

import { IdentifierLib } from "../../libs/IdentifierLib.sol";
import { OutputEncodingLib } from "../../libs/OutputEncodingLib.sol";
import { BaseOracle } from "../BaseOracle.sol";

import { GaslessCrossChainOrder } from "../../interfaces/IERC7683.sol";

/**
 * @dev Bitcoin oracle can operate in 2 modes:
 * 1. Directly Oracle. This requires a local light client along side the relevant reactor.
 * 2. Indirectly oracle through a bridge oracle.
 * This requires a local light client and a bridge connection to the relevant reactor.
 *
 * This oracle only works on EVM since it requires the original order to compute an orderID
 * which is used for the optimistic content.
 *
 * This filler can work as both an oracle
 * 0xB17C012
 */
contract BitcoinOracle is BaseOracle {
    error BadAmount(); // 0x749b5939
    error BadTokenFormat(); // 0x6a6ba82d
    error BlockhashMismatch(bytes32 actual, bytes32 proposed); // 0x13ffdc7d
    error OrderIdMismatch(bytes32 provided, bytes32 computed);
    error NotClaimed();
    error AlreadyClaimed(bytes32 claimer);
    error AlreadyDisputed(address disputer);
    error Disputed();
    error NotDisputed();
    error AmountTooLarge();
    error TooEarly();
    error TooLate();

    /**
     * @dev WARNING! Don't read output.remoteOracle nor output.chainId when emitted by this oracle.
     */
    event OutputFilled(bytes32 orderId, bytes32 solver, uint32 timestamp, OutputDescription output);
    event OutputVerified(bytes32 verificationContext);

    // TODO: figure out a way to make the struct smaller. (Currently 4 slots.)
    struct ClaimedOrder {
        bytes32 solver;
        address sponsor;
        // Packed uint256, spread across 3 storage slots. Avoids using a fifth storage slot.
        uint96 amount1;
        uint96 amount2;
        address disputer;
        uint64 amount3;
        address token;
    }

    mapping(bytes32 orderId => ClaimedOrder) _claimedOrder;

    // The Bitcoin Identifier (0xBC) is set in the 20'th byte (from right). This ensures
    // implementations that are only reading the last 20 bytes, still notice this is a Bitcoin address.
    // It also makes it more difficult for there to be a collision (even though low numeric value
    // addresses are generally pre-compiles and thus would be safe).
    // This also standardizes support for other light clients coins (Lightcoin 0x1C?)
    bytes30 constant BITCOIN_AS_TOKEN = 0x000000000000000000000000BC0000000000000000000000000000000000;

    /**
     * @notice Used light client. If the contract is not overwritten, it is expected to be BitcoinPrism.
     */
    address public immutable LIGHT_CLIENT;
    address public immutable AUTO_DISPUTED_COLLATERAL;

    /**
     * @notice Require that the challenger provides X times the collateral of the claimant.
     */
    uint256 public constant CHALLENGER_COLLATERAL_FACTOR = 2;

    constructor(address _lightClient, address autoDisputedCollateralTo) payable {
        LIGHT_CLIENT = _lightClient;
        AUTO_DISPUTED_COLLATERAL = autoDisputedCollateralTo;
    }

    //--- Light Client Helpers ---//
    // Helper functions to aid integration of other light clients.
    // These functions are the only external calls needed to prove Bitcoin transactions.
    // If you are adding support for another light client, inherit this contract and
    // overwrite these functions.

    /**
     * @notice Helper function to get the latest block height.
     * Is used to validate confirmations
     * @dev Is intended to be overwritten if another SPV client than Prism is used.
     */
    function _getLatestBlockHeight() internal view virtual returns (uint256 currentHeight) {
        return currentHeight = IBtcPrism(LIGHT_CLIENT).getLatestBlockHeight();
    }

    /**
     * @notice Helper function to get the blockhash at a specific block number.
     * Is used to check if block headers are valid.
     * @dev Is intended to be overwritten if another SPV client than Prism is used.
     */
    function _getBlockHash(
        uint256 blockNum
    ) internal view virtual returns (bytes32 blockHash) {
        return blockHash = IBtcPrism(LIGHT_CLIENT).getBlockHash(blockNum);
    }

    //--- Bitcoin Helpers ---//

    /**
     * @notice Slices the timestamp from a Bitcoin block header.
     * @dev Before calling this function, make sure the header is 80 bytes.
     */
    function _getTimestampOfBlock(
        bytes calldata blockHeader
    ) internal pure returns (uint256 timestamp) {
        return timestamp = Endian.reverse32(uint32(bytes4(blockHeader[68:68 + 4])));
    }

    function _getTimestampOfPreviousBlock(bytes calldata previousBlockHeader, BtcTxProof calldata inclusionProof) internal pure returns (uint256 timestamp) {
        // Check that previousBlockHeader is 80 bytes. While technically not needed
        // since the hash of previousBlockHeader.length > 80 won't match the correct hash
        // this is a sanity check that if nothing else ensures that objectively bad
        // headers are never provided.
        require(previousBlockHeader.length == 80);

        // Get block hash of the previousBlockHeader.
        bytes32 proposedPreviousBlockHash = BtcProof.getBlockHash(previousBlockHeader);
        // Load the actual previous block hash from the header of the block we just proved.
        bytes32 actualPreviousBlockHash = bytes32(Endian.reverse256(uint256(bytes32(inclusionProof.blockHeader[4:36]))));
        if (actualPreviousBlockHash != proposedPreviousBlockHash) {
            revert BlockhashMismatch(actualPreviousBlockHash, proposedPreviousBlockHash);
        }

        // This is now provably the previous block. As a result, we return the timestamp of the previous block.
        return _getTimestampOfBlock(previousBlockHeader);
    }

    /**
     * @notice Returns the associated Bitcoin script given an order token (address type) & destination (script hash).
     * @param token Bitcoin signifier (is checked) and the address version.
     * @param scriptHash Bitcoin address identifier hash.
     * Depending on address version is: Public key hash, script hash, or witness hash.
     * @return script Bitcoin output script matching the given parameters.
     */
    function _bitcoinScript(bytes32 token, bytes32 scriptHash) internal pure returns (bytes memory script) {
        // Check for the Bitcoin signifier:
        if (bytes30(token) != BITCOIN_AS_TOKEN) revert BadTokenFormat();

        // Load address version.
        AddressType bitcoinAddressType = AddressType(uint8(uint256(token)));

        return BtcScript.getBitcoinScript(bitcoinAddressType, scriptHash);
    }

    /**
     * @notice Loads the number of confirmations from the second last byte of the token.
     * @dev "0" confirmations are converted into 1.
     * How long does it take for us to get 99,9% confidence that a transaction will
     * be confirmable. Examine n identically distributed exponentially random variables
     * with rate 1/10. The sum of the random variables are distributed gamma(n, 1/10).
     * The 99,9% quantile of the distribution can be found in R as qgamma(0.999, n, 1/10)
     * 1 confirmations: 69 minutes.
     * 3 confirmations: 112 minutes.
     * 5 confirmations: 148 minutes.
     * 7 confimrations: 181 minutes.
     * You may wonder why the delta decreases as we increase confirmations?
     * That is the law of large numbers in action.
     */
    function _getNumConfirmations(
        bytes32 token
    ) internal pure returns (uint8 numConfirmations) {
        // Shift 8 bits to move the second byte to the right. It is now the first byte.
        // Then select the first byte. Decode as uint8.
        numConfirmations = uint8(uint256(token) >> 8);
        // If numConfirmations == 0, set it to 1.
        numConfirmations = numConfirmations == 0 ? 1 : numConfirmations;
    }

    // --- Data Validation Function --- //

    /**
     * @notice The Bitcoin Oracle should also work as an filler if it sits locally on a chain.
     * We don't want to store 2 attests of proofs (filler and oracle uses different schemes) so we instead store the
     * payload attestation. That allows settlers to easily check if outputs has been filled but also if payloads
     * have been verified (incase the settler is on another chain than the light client).
     */
    function _isPayloadValid(
        bytes calldata payload
    ) internal view returns (bool) {
        return _attestations[block.chainid][bytes32(uint256(uint160(address(this))))][keccak256(payload)];
    }

    /**
     * @dev Allows oracles to verify we have confirmed payloads.
     */
    function arePayloadsValid(
        bytes[] calldata payloads
    ) external view returns (bool) {
        uint256 numPayloads = payloads.length;
        for (uint256 i; i < numPayloads; ++i) {
            if (!_isPayloadValid(payloads[i])) return false;
        }
        return true;
    }

    // --- Validation --- //

    /**
     * @notice Verifies the existence of a Bitcoin transaction and returns the number of satoshis associated
     * with output txOutIx of the transaction.
     * @dev Does not return _when_ it happened except that it happened on blockNum.
     * @param minConfirmations Number of confirmations before transaction is considered valid.
     * @param blockNum Block number of the transaction.
     * @param inclusionProof Proof for transaction & transaction data.
     * @param txOutIx Index of the outputs to be examined against for output script and sats.
     * @param outputScript The expected output script. Compared to the actual, reverts if different.
     * @param embeddedData If provided (!= 0x), the next output (txOutIx+1) is checked to contain
     * the spend script: OP_RETURN | PUSH_(embeddedData.length) | embeddedData
     * See the Prism library BtcScript for more information.
     * @return sats Value of txOutIx TXO of the transaction.
     */
    function _validateUnderlyingPayment(
        uint256 minConfirmations,
        uint256 blockNum,
        BtcTxProof calldata inclusionProof,
        uint256 txOutIx,
        bytes memory outputScript,
        bytes calldata embeddedData
    ) internal view virtual returns (uint256 sats) {
        // Isolate height check. This slightly decreases gas cost.
        {
            uint256 currentHeight = _getLatestBlockHeight();

            if (currentHeight < blockNum) revert NoBlock(currentHeight, blockNum);

            unchecked {
                // Unchecked: currentHeight >= blockNum => currentHeight - blockNum >= 0
                // Bitcoin block heights are smaller than timestamp :)
                if (currentHeight + 1 - blockNum < minConfirmations) {
                    revert TooFewConfirmations(currentHeight + 1 - blockNum, minConfirmations);
                }
            }
        }

        // Load the expected hash for blockNum. This is the "security" call of the light client.
        // If block hash matches the hash of inclusionProof.blockHeader then we know it is a
        // valid block.
        bytes32 blockHash = _getBlockHash(blockNum);

        bytes memory txOutScript;
        bytes memory txOutData;
        if (embeddedData.length > 0) {
            // Important, this function validate that blockHash = hash(inclusionProof.blockHeader);
            // This function fails if txOutIx + 1 does not exist.
            (sats, txOutScript, txOutData) = BtcProof.validateTxData(blockHash, inclusionProof, txOutIx);

            if (!BtcProof.compareScripts(outputScript, txOutScript)) revert ScriptMismatch(outputScript, txOutScript);

            // Get the expected op_return script: OP_RETURN | PUSH_(embeddedData.length) | embeddedData
            bytes memory opReturnData = BtcScript.embedOpReturn(embeddedData);
            if (!BtcProof.compareScripts(opReturnData, txOutData)) revert ScriptMismatch(opReturnData, txOutData);
            return sats;
        }

        // Important, this function validate that blockHash = hash(inclusionProof.blockHeader);
        (sats, txOutScript) = BtcProof.validateTx(blockHash, inclusionProof, txOutIx);

        if (!BtcProof.compareScripts(outputScript, txOutScript)) revert ScriptMismatch(outputScript, txOutScript);
    }

    /**
     * @dev This function does not validate that the output is for this contract.
     * Instead it assumes that the caller correctly identified that this contract is the proper
     * contract to call. This is fine, since we never read the chainId nor remoteOracle
     * when setting the payload as proven.
     */
    function _verify(bytes32 orderId, OutputDescription calldata output, uint256 blockNum, BtcTxProof calldata inclusionProof, uint256 txOutIx, uint256 timestamp) internal {
        bytes32 token = output.token;
        bytes memory outputScript = _bitcoinScript(token, output.recipient);
        uint256 numConfirmations = _getNumConfirmations(token);
        uint256 sats = _validateUnderlyingPayment(numConfirmations, blockNum, inclusionProof, txOutIx, outputScript, output.remoteCall);

        // Check that the amount matches exactly. This is important since if the assertion
        // was looser it will be much harder to protect against "double spends".
        if (sats != output.amount) revert BadAmount();

        // Get the solver of the order.
        bytes32 solver = _resolveClaimed(orderId);

        // Store attestation.
        bytes32 outputHash = keccak256(OutputEncodingLib.encodeFillDescription(solver, orderId, uint32(timestamp), output));
        _attestations[block.chainid][bytes32(uint256(uint160(address(this))))][outputHash] = true;

        // We need to emit this event to make the output recognisably observably filled off-chain.
        emit OutputFilled(orderId, solver, uint32(timestamp), output);
        emit OutputVerified(inclusionProof.txId);
    }

    /**
     * @notice Validate an output is correct.
     * @dev Specifically, this function uses the other validation functions and adds some
     * Bitcoin context surrounding it.
     * @param output Output to prove.
     * @param blockNum Bitcoin block number of the transaction that the output is included in.
     * @param inclusionProof Proof of inclusion. fillDeadline is validated against Bitcoin block timestamp.
     * @param txOutIx Index of the output in the transaction being proved.
     */
    function _verifyAttachTimestamp(bytes32 orderId, OutputDescription calldata output, uint256 blockNum, BtcTxProof calldata inclusionProof, uint256 txOutIx) internal {
        // Check the timestamp. This is done before inclusionProof is checked for validity
        // so it can be manipulated but if it has been manipulated the later check (_validateUnderlyingPayment)
        // won't pass. _validateUnderlyingPayment checks if inclusionProof.blockHeader == 80.
        uint256 timestamp = _getTimestampOfBlock(inclusionProof.blockHeader);

        _verify(orderId, output, blockNum, inclusionProof, txOutIx, timestamp);
    }

    /**
     * @notice Function overload of _verify but allows specifying an older block.
     * @dev This function technically extends the verification of outputs 1 block (~10 minutes)
     * into the past beyond what _validateTimestamp would ordinary allow.
     * The purpose is to protect against slow block mining. Even if it took days to mine 1 block for a transaction,
     * it would still be possible to include the proof with a valid time. (assuming the oracle period isn't over yet).
     */
    function _verifyAttachTimestamp(bytes32 orderId, OutputDescription calldata output, uint256 blockNum, BtcTxProof calldata inclusionProof, uint256 txOutIx, bytes calldata previousBlockHeader) internal {
        // Get the timestamp of block before the one we that the transaction was included in.
        uint256 timestamp = _getTimestampOfPreviousBlock(previousBlockHeader, inclusionProof);

        _verify(orderId, output, blockNum, inclusionProof, txOutIx, timestamp);
    }

    /**
     * @notice Validate an output is correct and included in a block with appropriate confiration.
     * @param orderId Identifier for the order. Is used to check that the order has been correctly proviced
     * and to find the associated claim.
     * @param order Order containing the output to prove. Is used to validate the claim on the order id.
     * @param outputIndex Output index of the order to prove.
     * @param blockNum Bitcoin block number of block that included the transaction.
     * @param inclusionProof Proof of inclusion.
     * @param txOutIx Index of the output in the transaction being proved.
     */
    function verify(bytes32 orderId, CatalystCompactFilledOrder calldata order, uint256 outputIndex, uint256 blockNum, BtcTxProof calldata inclusionProof, uint256 txOutIx) external {
        bytes32 computedOrderId = _orderIdentifier(order);
        if (computedOrderId != orderId) revert OrderIdMismatch(orderId, computedOrderId);

        _verifyAttachTimestamp(orderId, order.outputs[outputIndex], blockNum, inclusionProof, txOutIx);
    }

    /**
     * @notice Function overload of verify but allows specifying an older block.
     * @dev This function technically extends the verification of outputs 1 block (~10 minutes)
     * into the past beyond what _validateTimestamp would ordinary allow.
     * The purpose is to protect against slow block mining. Even if it took days to get confirmation on a transaction,
     * it would still be possible to include the proof with a valid time. (assuming the oracle period isn't over yet).
     */
    function verify(
        bytes32 orderId,
        CatalystCompactFilledOrder calldata order,
        uint256 outputIndex,
        uint256 blockNum,
        BtcTxProof calldata inclusionProof,
        uint256 txOutIx,
        bytes calldata previousBlockHeader
    ) external {
        bytes32 computedOrderId = _orderIdentifier(order);
        if (computedOrderId != orderId) revert OrderIdMismatch(orderId, computedOrderId);

        _verifyAttachTimestamp(orderId, order.outputs[outputIndex], blockNum, inclusionProof, txOutIx, previousBlockHeader);
    }

    // --- Optimistic Resolution AND Order-Preclaiming --- //
    // For Bitcoin, it is required that outputs are claimed before they are delivered.
    // This is because it is impossible to block duplicate deliveries on Bitcoin in the same way
    // that is possible with EVM. (Actually, not true. It is just much more expensive – any-spend anchors).

    /**
     * @dev This settler and oracle only works with the TheCompactOrderType and not with other custom order types.
     */
    function _orderIdentifier(
        CatalystCompactFilledOrder calldata order
    ) internal view virtual returns (bytes32) {
        return TheCompactOrderType.orderIdentifier(order);
    }

    // --- Pre-claiming of outputs --- //

    /**
     * @notice Packs a uint256 amount into 3 uint fragments
     */
    function _packAmount(
        uint256 amount
    ) internal pure returns (uint96 amount1, uint96 amount2, uint64 amount3) {
        if (amount > type(uint192).max) revert AmountTooLarge();
        amount1 = uint96(amount);
        amount2 = uint96(amount >> 96);
        amount3 = uint64(amount >> (96 + 64));
    }

    /**
     * @notice Unpacks 3 uint fragments into a uint256.
     */
    function _unpackAmount(uint96 amount1, uint96 amount2, uint64 amount3) internal pure returns (uint256 amount) {
        amount = (amount3 << (96 + 64)) + (amount2 << 96) + amount1;
    }

    /**
     * @notice Returns the solver associated with the claim.
     * @dev Allows reentry calls. Does not honor the check effect pattern globally.
     */
    function _resolveClaimed(
        bytes32 orderId
    ) internal returns (bytes32 solver) {
        ClaimedOrder storage claimedOrder = _claimedOrder[orderId];
        solver = claimedOrder.solver;
        if (solver == bytes32(0)) revert NotClaimed();

        // Check if there are outstanding collateral associated with the
        // registered claim.
        address sponsor = claimedOrder.sponsor;
        uint96 amount1 = claimedOrder.amount1;
        if (sponsor != address(0)) {
            uint96 amount2 = claimedOrder.amount2;
            bool disputed = claimedOrder.disputer != address(0);
            uint64 amount3 = claimedOrder.amount3;
            address collateralToken = claimedOrder.token;
            uint256 collateralAmount = _unpackAmount(amount1, amount2, amount3);
            // If the order has been disputed, we need to also collect the disputers collateral for the solver.
            collateralAmount = disputed ? collateralAmount * (CHALLENGER_COLLATERAL_FACTOR + 1) : collateralAmount;

            // Delete storage so no re-entry.
            delete claimedOrder.sponsor;
            delete claimedOrder.amount1;
            delete claimedOrder.amount2;
            delete claimedOrder.disputer;
            delete claimedOrder.amount3;
            delete claimedOrder.token;

            SafeTransferLib.safeTransfer(collateralToken, sponsor, collateralAmount);
        }
    }

    /**
     * @notice Claim an order.
     * @dev Only works when the order identifier is exactly as on EVM.
     * @param solver Identifier to set as the solver.
     * @param orderId Order Identifier. Is used to validate the order has been correctly provided.
     * @param order The order containing the optimistic parameters
     */
    function claim(bytes32 solver, bytes32 orderId, CatalystCompactFilledOrder calldata order) external {
        bytes32 computedOrderId = _orderIdentifier(order);
        if (computedOrderId != orderId) revert OrderIdMismatch(orderId, computedOrderId);

        // Check that this order hasn't been claimed before.
        ClaimedOrder storage claimedOrder = _claimedOrder[orderId];
        if (claimedOrder.solver != bytes32(0)) revert AlreadyClaimed(claimedOrder.solver);
        uint256 collateralAmount = order.collateralAmount;
        address collateralToken = order.collateralToken;
        (uint96 amount1, uint96 amount2, uint64 amount3) = _packAmount(collateralAmount);

        claimedOrder.solver = solver;
        claimedOrder.sponsor = msg.sender;
        claimedOrder.amount1 = amount1;
        claimedOrder.amount2 = amount2;
        if (order.challengeDeadline == order.initiateDeadline) claimedOrder.disputer = AUTO_DISPUTED_COLLATERAL;
        claimedOrder.amount3 = amount3;
        claimedOrder.token = collateralToken;
        // The above lines acts as a local re-entry guard. External calls are now allowed.

        if (order.initiateDeadline < block.timestamp) revert TooLate();
        if (order.challengeDeadline < block.timestamp) revert TooLate();

        // Collect collateral from claimant.
        SafeTransferLib.safeTransferFrom(collateralToken, msg.sender, address(this), collateralAmount);
    }

    /**
     * @notice Dispute an order.
     * @param orderId Order Identifier. Is used to validate the order has been correctly provided.
     * @param order The order containing the optimistic parameters
     */
    function dispute(bytes32 orderId, CatalystCompactFilledOrder calldata order) external {
        bytes32 computedOrderId = _orderIdentifier(order);
        if (computedOrderId != orderId) revert OrderIdMismatch(orderId, computedOrderId);
        if (order.challengeDeadline < block.timestamp) revert TooLate();

        // Check that this order has been claimed but not disputed..
        ClaimedOrder storage claimedOrder = _claimedOrder[orderId];
        if (claimedOrder.solver == bytes32(0)) revert NotClaimed();
        if (claimedOrder.disputer != address(0)) revert AlreadyDisputed(claimedOrder.disputer);
        claimedOrder.disputer = msg.sender;

        address collateralToken = order.collateralToken;
        uint256 collateralAmount = order.collateralAmount * CHALLENGER_COLLATERAL_FACTOR;

        // Collect collateral from disputer.
        SafeTransferLib.safeTransferFrom(collateralToken, msg.sender, address(this), collateralAmount);
    }

    /**
     * @notice Optimistically verify an order if the order has not been disputed.
     * @dev Sets all outputs belonging to this contract as validated on storage
     */
    function optimisticallyVerify(
        CatalystCompactFilledOrder calldata order
    ) external {
        if (order.challengeDeadline >= block.timestamp) revert TooEarly();

        bytes32 orderId = _orderIdentifier(order);

        ClaimedOrder storage claimedOrder = _claimedOrder[orderId];
        bool disputed = claimedOrder.disputer != address(0);
        if (disputed) revert Disputed();

        bytes32 solver = claimedOrder.solver;
        address sponsor = claimedOrder.sponsor;

        // Delete the claim details.
        delete claimedOrder.solver;
        delete claimedOrder.sponsor;
        delete claimedOrder.amount1;
        delete claimedOrder.amount2;
        delete claimedOrder.disputer;
        delete claimedOrder.amount3;
        delete claimedOrder.token;

        uint32 challengeDeadline = order.challengeDeadline;

        // Go through each output and the ones that correspond to this contract, set them.
        uint256 numOutputs = order.outputs.length;
        for (uint256 i; i < numOutputs; ++i) {
            OutputDescription calldata output = order.outputs[i];
            // Is this us?
            // Check if we are the sole oracle OR we are the in the rightmost 16 bytes.
            bool isOurChain = block.chainid == output.chainId;
            if (!isOurChain) continue;
            bool IsOurContract = output.remoteOracle == bytes32(uint256(uint160(address(this)))) // Sole
                || (bytes16(output.remoteOracle) == bytes16(bytes32((IdentifierLib.countLeadingZeros(uint160(address(this))) << 248) + (uint256(uint160(address(this))) << 136) >> 8))); // Rightmost 16
            if (!IsOurContract) continue;
            bytes32 outputHash = keccak256(OutputEncodingLib.encodeFillDescription(solver, orderId, uint32(challengeDeadline), output));
            _attestations[block.chainid][bytes32(uint256(uint160(address(this))))][outputHash] = true;
        }

        SafeTransferLib.safeTransfer(order.collateralToken, sponsor, order.collateralAmount);
    }

    /**
     * @notice Finalise a dispute if the order hasn't been proven.
     */
    function finaliseDispute(
        CatalystCompactFilledOrder calldata order
    ) external {
        if (order.fillDeadline >= block.timestamp) revert TooEarly();
        bytes32 orderId = _orderIdentifier(order);

        ClaimedOrder storage claimedOrder = _claimedOrder[orderId];
        address disputer = claimedOrder.disputer;
        if (disputer == address(0)) revert NotDisputed();
        // Delete the dispute details.
        delete claimedOrder.solver;
        delete claimedOrder.sponsor;
        delete claimedOrder.amount1;
        delete claimedOrder.amount2;
        delete claimedOrder.disputer;
        delete claimedOrder.amount3;
        delete claimedOrder.token;

        address collateralToken = order.collateralToken;
        uint256 collateralAmount = order.collateralAmount * (CHALLENGER_COLLATERAL_FACTOR + 1);
        SafeTransferLib.safeTransfer(collateralToken, disputer, collateralAmount);
    }
}
