// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IOracle } from "../../interfaces/IOracle.sol";

import { IsContractLib } from "../../libs/IsContractLib.sol";

import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    IOriginSettler,
    ResolvedCrossChainOrder,
    Output,
    FillInstruction
} from "../../interfaces/IERC7683.sol";

import { CatalystOrderData, InputDescription, OutputDescription } from "../CatalystOrderType.sol";

import {
    InvalidSettlementAddress,
    WrongChain,
    InitiateDeadlinePassed,
    CannotProveOrder
} from "../../interfaces/Errors.sol";

/**
 * @title Base Cross-chain intent Reactor
 * @notice Cross-chain intent resolver. Implements core logic that is shared between all
 * reactors like token collection, order interfaces, order resolution:
 * - Optimistic Payout: Orders are assumed to have been filled correctly by the solver if not disputed.
 * - Order Dispute: Orders can be disputed such that proof of fulfillment has to be made.
 * - Oracle Interaction: To provide the relevant proofs against order disputes.
 *
 * It is expected that proper order reactors implement:
 * - `_initiate`. To convert partially structured orders into order keys that describe fulfillment conditions.
 * - `_resolveKey`. Helper function to convert an order into an order key.
 * You can find more information about these in ./helpers/ResolverAbstractions.sol
 * @dev Important implementation quirks:
 * **Token Trust**
 * There is a lot of trust put into the tokens that interact with the contract. Not trust as in the tokens can
 * impact this contract but trust as in a faulty / malicious token may be able to break the order status flow
 * and prevent proper delivery of inputs (to solver) and return of collateral.
 * As a result, it is important that users are aware of the following usage restrictions:
 * 1. Don't use a pausable/blacklist token if there is a risk that one of the actors (user / solver)
 * being paused. This also applies from the user's perspective, if a pausable token is used for
 * collateral their inputs may not be returnable.
 * 2. All inputs have to be trusted by all parties. If one input is unable to be transferred, the whole lot
 * becomes stuck until the issue is resolved.
 * 3. Solvers should validate that they can fill the outputs otherwise their collateral may be at risk and it could
 * annoy users.
 */
contract BaseSettler {
    error AlreadyPurchased();
    bytes32 public constant VERSION_FLAGS = bytes32(uint256(2));

    uint256 DISCOUNT_DENOM = 10**18;

    struct PurchaseConfig {
        uint40 timeToBuy;
        uint48 discount;
    }

    // TODO: This needs to be 1 slot.
    struct Purchased {
        // TODO: Merge the 2 variables.
        uint40 purchasedAt;
        uint40 timeToBuy;
        address purchaser;
    }

    mapping(bytes32 solver => PurchaseConfig) public purchaseConfig;
    mapping(bytes32 solver => mapping(bytes32 orderId => Purchased)) public purchasedOrders;

    //--- Hashing Orders ---//

    // TODO: Make a proper hashing function.
    function _orderIdentifier(GaslessCrossChainOrder calldata order) pure internal returns(bytes32) {
        return keccak256(abi.encode(order));
    }

    function orderIdentifier(GaslessCrossChainOrder calldata order) pure external returns(bytes32) {
        return _orderIdentifier(order);
    }

    function _orderIdentifier(OnchainCrossChainOrder calldata order) pure internal returns(bytes32) {
        return keccak256(abi.encode(order));
    }

    function orderIdentifier(OnchainCrossChainOrder calldata order) pure external returns(bytes32) {
        return _orderIdentifier(order);
    }

    //--- Order Validation ---//

    function _validateOrder(GaslessCrossChainOrder calldata order) internal view {
        // Check that we are the settler for this order:
        if (address(this) != order.originSettler) revert InvalidSettlementAddress();
        // Check that this is the right originChain
        if (block.chainid != order.originChainId) revert WrongChain(block.chainid, order.originChainId);
        // Check if the open deadline has been passed
        if (block.timestamp > order.openDeadline) revert InitiateDeadlinePassed();
    }

    //--- Order Purchase Helpers ---//

    function configurePurchaseOrder() external {


        // TODO: event
    }

    /**
     * @notice This function is called from whoever wants to buy an order from a filler and gain a reward
     * @dev If you are buying a challenged order, ensure that you have sufficient time to prove the order or
     * your funds may be at risk.
     * Set newPurchaseDeadline in the past to disallow future takeovers.
     * When you purchase orders, make sure you take into account that you are paying the
     * entirety while you will get out the entirety MINUS any governance fee.
     * If you are calling this function from an external contract, beaware of re-entry
     * issues from a later execute. (configured of fillerData).
     */
    function purchaseOrder(bytes32 orderSolvedByIdentifier, GaslessCrossChainOrder calldata order, address purchaser, uint256 expiryTimestamp, uint256 minDiscount) external {
        require(purchaser != address(0));
        require(expiryTimestamp > block.timestamp);

        bytes32 orderId = _orderIdentifier(order);
        // Check if the order has been purchased already.
        Purchased storage purchased = purchasedOrders[orderSolvedByIdentifier][orderId];
        if (purchased.purchaser != address(0)) revert AlreadyPurchased();

        // Load the config of the last purchaser.
        PurchaseConfig storage solverConfig = purchaseConfig[orderSolvedByIdentifier];
        uint256 discount = solverConfig.discount;
        uint40 timeToBuy = solverConfig.timeToBuy;
        require(discount != 0);
        require(timeToBuy != 0);
        // The discount needs to be smaller than the one called by. (Large discount => you pay more.) This is to protect against a bait and switch by the solver.
        if (discount < minDiscount) require(false); // TODO: revert with DiscountTooLow.

        // Reentry protection. Ensure that you can't reenter this contract.
        purchased.purchasedAt = uint40(block.timestamp);
        purchased.timeToBuy = timeToBuy;
        purchased.purchaser = purchaser;
        // We can now make external calls without allowing local reentries into this call.

        // Pay out the input tokens to the solver.
        CatalystOrderData memory orderData = abi.decode(order.orderData, (CatalystOrderData));
        uint256 numInputs = orderData.inputs.length;
        address orderSolvedByAddress = address(uint160(uint256(orderSolvedByIdentifier)));
        for (uint256 i; i < numInputs; ++i) {
            InputDescription memory inputDescription = orderData.inputs[i];
            uint256 amountAfterDiscount = inputDescription.amount * discount / DISCOUNT_DENOM;
            SafeTransferLib.safeTransferFrom(address(uint160(inputDescription.tokenId)), msg.sender, orderSolvedByAddress, amountAfterDiscount);
        }

        // emit OrderPurchased(orderId, purchaser);
    }

    //--- ERC7683 Resolvers ---//

    function _resolve(
        CatalystOrderData memory orderData,
        address filler
    ) internal view virtual returns (Output[] memory maxSpent, FillInstruction[] memory fillInstructions, Output[] memory minReceived) {
        uint256 numOutputs = orderData.outputs.length;
        maxSpent = new Output[](numOutputs);
        
        // If the output list is sorted by chains, this list is unqiue and optimal.
        fillInstructions = new FillInstruction[](numOutputs);
        for (uint256 i = 0; i < numOutputs; ++i) {
            OutputDescription memory catalystOutput = orderData.outputs[i];
            uint256 chainId = catalystOutput.chainId;
            maxSpent[i] = Output({
                token: catalystOutput.token,
                amount: catalystOutput.amount,
                recipient: catalystOutput.recipient,
                chainId: chainId
            });
            fillInstructions[i] = FillInstruction({
                destinationChainId: uint64(chainId),
                destinationSettler: catalystOutput.remoteOracle,
                originData: abi.encode(catalystOutput)
            });
        }

        // fillerOutputs are of the Output type and as a result, we can't just
        // load swapperInputs into fillerOutputs. As a result, we need to parse
        // the individual inputs and make a new struct.
        uint256 numInputs = orderData.inputs.length;
        minReceived = new Output[](numInputs);
        unchecked {
            for (uint256 i; i < numInputs; ++i) {
                InputDescription memory input = orderData.inputs[i];
                minReceived[i] = Output({
                    token: bytes32(uint256(uint160(input.tokenId))),
                    amount: input.amount,
                    recipient: bytes32(uint256(uint160(filler))),
                    chainId: uint32(block.chainid)
                });
            }
        }
    }

    /**
     * @notice Resolves an order into an ERC-7683 compatible order struct.
     * By default relies on _resolveKey to convert OrderKey into a ResolvedCrossChainOrder
     * @dev Can be overwritten if there isn't a translation of an orderKey into resolvedOrder.
     * @param order CrossChainOrder to resolve.
     * @return resolvedOrder ERC-7683 compatible order description, including the inputs and outputs of the order
     */
    function _resolve(
        GaslessCrossChainOrder calldata order,
        address filler
    ) internal view virtual returns (ResolvedCrossChainOrder memory resolvedOrder) {
        CatalystOrderData memory orderData = abi.decode(order.orderData, (CatalystOrderData));

        (Output[] memory maxSpent, FillInstruction[] memory fillInstructions, Output[] memory minReceived) = _resolve(orderData, filler);

        // Lastly, complete the ResolvedCrossChainOrder struct.
        resolvedOrder = ResolvedCrossChainOrder({
            user: order.user,
            originChainId: order.originChainId,
            openDeadline: order.openDeadline,
            fillDeadline: order.fillDeadline,
            orderId: _orderIdentifier(order),
            maxSpent: maxSpent,
            minReceived: minReceived,
            fillInstructions: fillInstructions
        });
    }

    function _resolve(
        OnchainCrossChainOrder calldata order,
        address filler
    ) internal view virtual returns (ResolvedCrossChainOrder memory resolvedOrder) {
        CatalystOrderData memory orderData = abi.decode(order.orderData, (CatalystOrderData));

        (Output[] memory maxSpent, FillInstruction[] memory fillInstructions, Output[] memory minReceived) = _resolve(orderData, filler);

        // Lastly, complete the ResolvedCrossChainOrder struct.
        resolvedOrder = ResolvedCrossChainOrder({
            user: address(0),
            originChainId: block.chainid,
            openDeadline: 0,
            fillDeadline: order.fillDeadline,
            orderId: _orderIdentifier(order),
            maxSpent: maxSpent,
            minReceived: minReceived,
            fillInstructions: fillInstructions
        });
    }

    /**
     * @notice ERC-7683: Resolves a specific CrossChainOrder into a generic ResolvedCrossChainOrder
     * @dev Intended to improve standardized integration of various order types and settlement contracts
     * @param order CrossChainOrder to resolve.
     * @return resolvedOrder ERC-7683 compatible order description, including the inputs and outputs of the order
     */
    function resolve(
        OnchainCrossChainOrder calldata order
    ) external view returns (ResolvedCrossChainOrder memory resolvedOrder) {
        return _resolve(order, address(0));
    }

    function resolveFor(
        GaslessCrossChainOrder calldata order,
        bytes calldata /* signature */,
        bytes calldata /* originFllerData */
    ) external view returns (ResolvedCrossChainOrder memory resolvedOrder) {
        return _resolve(order, address(0));
    }
}
