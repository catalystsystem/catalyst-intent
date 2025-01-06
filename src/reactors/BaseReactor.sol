// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IOracle } from "../interfaces/IOracle.sol";
import { OrderContext, OrderKey, OrderStatus, OutputDescription, ReactorInfo } from "../interfaces/Structs.sol";

import { FillerDataLib } from "../libs/FillerDataLib.sol";
import { IsContractLib } from "../libs/IsContractLib.sol";

import {
    GasslessCrossChainOrder,
    OnchainCrossChainOrder,
    IOriginSettler
} from "../interfaces/IERC7683.sol";

import {
    ITheCompactClaims
} from "the-compact/src/interfaces/ITheCompactClaims.sol";

import {
    CannotCancelOrder,
    CannotProveOrder,
    ChallengeDeadlinePassed,
    DepositDoesntExist,
    DepositExists,
    InitiateDeadlineAfterFill,
    InitiateDeadlinePassed,
    InvalidDeadlineOrder,
    InvalidSettlementAddress,
    MinOrderPurchaseDiscountTooLow,
    OnlyFiller,
    OrderAlreadyClaimed,
    OrderNotReadyForOptimisticPayout,
    OrderFinal,
    ProofPeriodHasNotPassed,
    PurchaseTimePassed,
    WrongChain,
    WrongOrderStatus
} from "../interfaces/Errors.sol";
import { ReactorPayments } from "./helpers/ReactorPayments.sol";
import { ResolverERC7683 } from "./helpers/ResolverERC7683.sol";
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

abstract contract BaseReactor is ReactorPayments, ResolverERC7683 {
    bytes32 public constant VERSION_FLAGS = bytes32(uint256(1));

    /**
     * @notice An order has been initiated.
     */
    event OrderInitiated(bytes32 indexed orderHash, address indexed caller, bytes filler, OrderKey orderKey);

    /**
     * @notice An order has been proven and settled.
     */
    event OrderProven(bytes32 indexed orderHash, address indexed prover);

    /**
     * @notice An order has been optimistically resolved.
     */
    event OptimisticPayout(bytes32 indexed orderHash);

    /**
     * @notice An order has ben challenged.
     */
    event OrderChallenged(bytes32 indexed orderHash, address indexed disputer);

    /**
     * @notice A challenged order was not proven and enough time has passed
     * since it was challenged so it has been assumed no delivery was made.
     */
    event FraudAccepted(bytes32 indexed orderHash);

    /**
     * @notice An order has been purchased by someone else and the filler has changed.
     */
    event OrderPurchased(bytes32 indexed orderHash, address newFiller);

    /**
     * @notice The order purchase details have been modified by the filler.
     */
    event OrderPurchaseDetailsModified(bytes32 indexed orderHash, bytes fillerdata);

    /**
     * @notice New order has been broadcasted.
     */
    event OrderBroadcast(bytes32 indexed orderHash, CrossChainOrder order, bytes signature);

    /**
     * @notice OrderHash
     */
    event OrderDeposited(CrossChainOrder order);

    //--- Mappings ---//

    /**
     * @notice Maps an orderkey hash to the relevant orderContext.
     */
    mapping(bytes32 orderKeyHash => OrderContext orderContext) internal _orders;

    /**
     * @notice Maps a crossChainOrderHash to a deposited statement.
     * Not to be confused with an orderKeyHash.
     */
    mapping(bytes32 crossChainOrderHash => bool) internal _deposits;


    constructor(address permit2, address owner) payable ReactorPayments(permit2, owner) { }

    //--- Hashing Orders ---//

    function _orderKeyHash(
        OrderKey memory orderKey
    ) internal pure returns (bytes32 orderKeyHash) {
        return orderKeyHash = keccak256(abi.encode(orderKey));
    }

    function getOrderKeyHash(
        OrderKey calldata orderKey
    ) external pure returns (bytes32 orderKeyHash) {
        return orderKeyHash = _orderKeyHash(orderKey);
    }

    function _crossChainOrderHash(
        CrossChainOrder calldata order
    ) internal pure returns (bytes32 crossChainOrderHash) {
        return crossChainOrderHash = keccak256(abi.encode(order));
    }

    function getCrossChainOrderHash(
        CrossChainOrder calldata order
    ) external pure returns (bytes32 crossChainOrderHash) {
        return crossChainOrderHash = _crossChainOrderHash(order);
    }

    //--- Expose Storage ---//

    function getOrderContext(
        bytes32 orderKeyHash
    ) external view returns (OrderContext memory orderContext) {
        return orderContext = _orders[orderKeyHash];
    }

    function getOrderContext(
        OrderKey calldata orderKey
    ) external view returns (OrderContext memory orderContext) {
        return orderContext = _orders[_orderKeyHash(orderKey)];
    }

    modifier preVerification(CrossChainOrder calldata order) {
        // Check if this is the right contract.
        if (order.settlementContract != address(this)) revert InvalidSettlementAddress();
        // Check if the expected chain of the order is the rigtht one.
        if (order.originChainId != block.chainid) revert WrongChain(uint32(block.chainid), order.originChainId);

        // Check if initiate Deadline has passed.
        if (order.initiateDeadline < block.timestamp) revert InitiateDeadlinePassed();

        // The order initiation must be less than the fill deadline. Both of them cannot be the current time as well.
        // Fill deadline must be after initiate deadline. Otherwise the solver is prone to making a mistake.
        if (order.fillDeadline < order.initiateDeadline) revert InitiateDeadlineAfterFill();
        
        // Notice that the 2 above checks also ensures that order.fillDeadline > block.timestamp since
        // block.timestamp <= order.initiateDeadline && order.initiateDeadline <= order.fillDeadline
        // => block.timestamp <= order.fillDeadline
        _;
    }


    //--- Order Handling ---//

    function open(
        GasslessCrossChainOrder calldata order
    ) external {
        // Check that we are the settler for this order:
        if (address(this) != order.originSettler) revert InvalidSettlementAddress();
        // Check that this is the right originChain
        if (block.chainid != order.originChainId) revert WrongChain(block.chainid, order.originChainId);
        // Check if the open deadline has been passed
        if (block.timestamp > order.openDeadline) revert InitiateDeadlinePassed();

        // Decode the order data.
        CatalystOrderData memory orderData = abi.decode(order, (CatalystOrderData));

        // Check if the order has been filled and get the solver.
        address solver = IOracle(orderKey.localOracle).outputFilled(orderKey.outputs, orderKey.reactorContext.fillDeadline);
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
     * @param signature The end user signature for the order
     * If an order has already been deposited, the signature is ignored.
     * @param fillerData Any filler-defined data required by the settler
     */

    function openFor(
        GasslessCrossChainOrder calldata order,
        bytes calldata signature,
        bytes calldata originFllerData
    ) external {
    }

    /**
     * @notice Prove that an order was filled. Requires that the order oracle exposes
     * a function, isProven(...), that returns true when called with the order details.
     * @dev If an order has configured some additional data that should be executed on
     * initiation, then this has to be provided here as executionData. If the executionData
     * is lost, then the filler should call `modifyOrderFillerdata` to set new executionData.
     * If you are calling this function from an external contract, beaware of re-entry
     * issues from a later execute. (configured of executionData).
     */
    /**
     * @notice This function is step 1 to initate a user's deposit.
     * It deposits the assets required for ´order´ into The Compact.
     */
     // TODO: get rid of btyes here
    function open(OnchainCrossChainOrder calldata order, bytes calldata asig, bytes calldata ssig, address solvedBy) external {
        bytes32 orderHash = _orderKeyHash(orderKey);
        OrderContext storage orderContext = _orders[orderHash];

        OrderStatus status = orderContext.status;
        address fillerAddress = orderContext.fillerAddress;

        // Only allow processing if order status is either claimed or challenged.
        if (status != OrderStatus.Claimed && status != OrderStatus.Challenged) {
            revert WrongOrderStatus(orderContext.status);
        }

        // Immediately set order status to proven. This causes the previous line to fail.
        // This acts as a LOCAL reentry check.
        orderContext.status = OrderStatus.Proven;

        // The following call is a external call to an untrusted contract. As a result,
        // it is important that we protect this contract against reentry calls, even if read-only.
        if (!IOracle(orderKey.localOracle).isProven(orderKey.outputs, orderKey.reactorContext.fillDeadline)) {
            revert CannotProveOrder();
        }

        // Payout inputs.
        _resolveLock(
            order, asig, ssig, solvedBy
        );

        bytes32 identifier = orderContext.identifier;
        if (identifier != bytes32(0)) FillerDataLib.execute(identifier, orderHash, orderKey.inputs, executionData);

        emit OrderProven(orderHash, msg.sender);
    }

    function resolveFor(
        GasslessCrossChainOrder calldata order,
        bytes calldata signature,
        bytes calldata originFllerData
    ) external view {

    }

    function resolve(OnchainCrossChainOrder calldata order) external view {

    }

    //--- Order Purchase Helpers ---//

    /**
     * @notice This function is called from whoever wants to buy an order from a filler and gain a reward
     * @dev If you are buying a challenged order, ensure that you have sufficient time to prove the order or
     * your funds may be at risk.
     * Set newPurchaseDeadline in the past to disallow future takeovers.
     * When you purchase orders, make sure you take into account that you are paying the
     * entirety while you will get out the entirety MINUS any governance fee.
     * If you are calling this function from an external contract, beaware of re-entry
     * issues from a later execute. (configured of fillerData).
     * @param orderKey Claimed order to be purchased from the filler.
     * @param fillerData New filler data + potential execution data post-pended.
     * @param minDiscount The minimum discount the new filler is willing to buy at.
     * Should be set to disallow someone frontrunning this call and decreasing the discount.
     */
    function purchaseOrder(OrderKey calldata orderKey, bytes calldata fillerData, uint256 minDiscount) external {
        bytes32 orderKeyHash = _orderKeyHash(orderKey);
        OrderContext storage orderContext = _orders[orderKeyHash];

        {
            OrderStatus status = orderContext.status;

            // The order should have been claimed and not paid / proven / fraud proven (inputs should be intact)
            // for it to be purchased.
            if (status != OrderStatus.Claimed && status != OrderStatus.Challenged) {
                revert WrongOrderStatus(orderContext.status);
            }
        }

        // The order cannot be purchased after the max time specified to be sold at has passed
        if (orderContext.orderPurchaseDeadline < block.timestamp) {
            revert PurchaseTimePassed();
        }

        // Decode filler data.
        (
            address fillerAddress,
            uint32 orderPurchaseDeadline,
            uint16 orderPurchaseDiscount,
            bytes32 identifier,
            uint256 fillerDataPointer
        ) = FillerDataLib.decode(fillerData);

        // Load old storage variables.
        address oldFillerAddress = orderContext.fillerAddress;
        uint16 oldOrderPurchaseDiscount = orderContext.orderPurchaseDiscount;
        bytes32 oldIdentifier = orderContext.identifier;
        // Check if the discount is good. Remember that a larger number is a better discount.
        if (minDiscount > oldOrderPurchaseDiscount) {
            revert MinOrderPurchaseDiscountTooLow(minDiscount, oldOrderPurchaseDiscount);
        }

        // We can now update the storage with the new filler data.
        // This allows us to avoid reentry protecting this function.
        orderContext.fillerAddress = fillerAddress;
        orderContext.orderPurchaseDeadline = orderPurchaseDeadline;
        orderContext.orderPurchaseDiscount = orderPurchaseDiscount;
        orderContext.identifier = identifier;

        // We can now make external calls without allowing local reentries into this call.

        // Collateral is paid for in full.
        address collateralToken = orderKey.collateral.collateralToken;
        uint256 collateralAmount = orderKey.collateral.fillerCollateralAmount;
        // No need to check if collateral is valid, since it has already entered the contract.
        if (collateralAmount > 0) SafeTransferLib.safeTransferFrom(collateralToken, msg.sender, oldFillerAddress, collateralAmount);

        // Transfer the ERC20 tokens. This requires explicit approval for this contract for each token.
        // This is not done through permit.
        // This function assumes the collection is from msg.sender, as a result we don't need to specify that.
        _collectTokensFromMsgSender(orderKey.inputs, oldFillerAddress, oldOrderPurchaseDiscount);

        // Check if there is an identifier, if there is execute data.
        if (oldIdentifier != bytes32(0)) {
            FillerDataLib.execute(identifier, orderKeyHash, orderKey.inputs, fillerData[fillerDataPointer:]);
        }

        emit OrderPurchased(orderKeyHash, msg.sender);
    }
}
