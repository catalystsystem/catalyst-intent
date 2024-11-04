// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IOracle } from "../interfaces/IOracle.sol";
import {
    CrossChainOrder,
    ISettlementContract,
    Input,
    Output,
    ResolvedCrossChainOrder
} from "../interfaces/ISettlementContract.sol";
import { OrderContext, OrderKey, OrderStatus, OutputDescription, ReactorInfo } from "../interfaces/Structs.sol";

import { FillerDataLib } from "../libs/FillerDataLib.sol";
import { IsContractLib } from "../libs/IsContractLib.sol";

import {
    CannotProveOrder,
    ChallengeDeadlinePassed,
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

    function getDepositStatus(
        CrossChainOrder calldata order
    ) external view returns (bool) {
        return _deposits[_crossChainOrderHash(order)];
    }

    //--- On-chain orderbook ---//

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

    /**
     * @notice Allows submitting order without an order server.
     * This can be used to bypass censorship or to make a on-chain transaction.
     * This contract is not sufficient and will allow invalid orders. It is expected that an off-chain entity will filter orders.
     */
    function broadcast(
        CrossChainOrder calldata order,
        bytes calldata signature
    ) external preVerification(order) {
        bytes32 orderHash = _orderKeyHash(_resolveKey(order, signature[0:0]));
        emit OrderBroadcast(orderHash, order, signature);
    }

    /**
     * @notice Pre-order initiation function. Is intended to be used to compose
     * @dev Is deposited to order.Swapper.
     * Note! The nonce is ignored for this use case. Each deposit remains valid perpetually.
     * After expiry, anyone can call the assets back to the swapper be canceling the order.
     * The swapper can cancel the order early.
     * 
     */
    function deposit(
        CrossChainOrder calldata order
    ) external preVerification(order) {
        // Check that no existing deposit exists.
        bool deposited = _deposits[_crossChainOrderHash(order)];
        if (deposited) require(false);
        // Set the deposit flag early to protect against reentry.
        _deposits[_crossChainOrderHash(order)] = true;
        
        Input[] memory inputs = _getMaxInputs(order);
        address to = address(this);
        uint16 discount = uint16(0);
        _collectTokensFromMsgSender(inputs, to, discount);

        emit OrderDeposited(order);
    }

    /**
     * @notice Allows someone to cancel an order early or collect a deposit that was never claimed by a solver.
     * 
     */
    function cancel(
        CrossChainOrder calldata order
    ) external {
        // If the initiate deadline hasn't been passed, the caller needs to be msg.sender.
        if (order.initiateDeadline < block.timestamp && order.swapper != msg.sender) require(false, "TODO");

        bool deposited = _deposits[_crossChainOrderHash(order)];
        if (!deposited) require(false);
        _deposits[_crossChainOrderHash(order)] = false;

        Input[] memory inputs = _getMaxInputs(order);
        _deliverTokens(inputs, order.swapper, 0);
    }

    //--- Order Handling ---//

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
    function initiate(
        CrossChainOrder calldata order,
        bytes calldata signature,
        bytes calldata fillerData
    ) external preVerification(order) returns (OrderKey memory orderKey) {
        // Decode filler data.
        (
            address fillerAddress,
            uint32 orderPurchaseDeadline,
            uint16 orderPurchaseDiscount,
            bytes32 identifier,
            uint256 fillerDataPointer
        ) = FillerDataLib.decode(fillerData);

        // Permit2 & EIP-712 object variables.
        bytes32 witness; // Hash of our struct to be combined with permit2's struct hash.
        string memory witnessTypeString; // Type of our order struct (witness).
        uint256[] memory permittedAmounts; // The amounts the user signed (derived from order).

        // Initiate order.
        (orderKey, permittedAmounts, witness, witnessTypeString) = _initiate(order, fillerData[fillerDataPointer:]);

        // The proof deadline should be the last deadline and it must be after the challenge deadline.
        // The challenger should be able to challenge after the order is filled.
        ReactorInfo memory reactorInfo = orderKey.reactorContext;
        // Check if: order.fillDeadline <= rI.challengeDeadline && rI.challengeDeadline <= rI.proofDeadline.
        // That implies if: order.fillDeadline > rI.challengeDeadline || rI.challengeDeadline > rI.proofDeadline
        // then the deadlines are invalid.
        if (
            order.fillDeadline > reactorInfo.challengeDeadline
                || reactorInfo.challengeDeadline > reactorInfo.proofDeadline
        ) {
            revert InvalidDeadlineOrder();
        }

        // Check that the order hasn't been claimed yet. We will then set the order status
        // so other can't claim it. This acts as a local reentry check.
        bytes32 orderHash = _orderKeyHash(orderKey);
        OrderContext storage orderContext = _orders[orderHash];
        // If an order has been configured such that it is free to challenge and impossible at the same time
        // (free === orderKey.collateral.challengerCollateralAmount == 0) && ("impossible" === orderKey.proofDeadline == orderKey.challengeDeadline)
        // then it is assumed that the order should be required to be strictly verified. (default challenged)
        bool defaultChallenge = (reactorInfo.proofDeadline == reactorInfo.challengeDeadline) && (orderKey.collateral.challengerCollateralAmount == 0);
        if (defaultChallenge) orderContext.challenger = orderKey.swapper;
        // Ideally the above section was moved below the orderContext check but there is a stack too deep issue if done so.

        OrderStatus status = orderContext.status;
        if (status != OrderStatus.Unfilled) revert OrderAlreadyClaimed(orderContext.status);
        orderContext.status = defaultChallenge ? OrderStatus.Challenged : OrderStatus.Claimed; // Now this order cannot be claimed again.
        orderContext.fillerAddress = fillerAddress;
        orderContext.orderPurchaseDeadline = orderPurchaseDeadline;
        orderContext.orderPurchaseDiscount = orderPurchaseDiscount;
        // Identifier is in its own storage slot.
        if (identifier != bytes32(0)) orderContext.identifier = identifier;


        // Check if the collateral token is indeed a contract. SafeTransferLib does not revert on no code.
        // This is important, since a later deployed token can screw up the whole pipeline.
        IsContractLib.checkCodeSize(orderKey.collateral.collateralToken);
        // Collateral is collected from sender instead of fillerAddress.
        SafeTransferLib.safeTransferFrom(
            orderKey.collateral.collateralToken, msg.sender, address(this), orderKey.collateral.fillerCollateralAmount
        );

        // Check if a user has already deposited for this order.
        bool deposited = _deposits[_crossChainOrderHash(order)];
        if (deposited) _deposits[_crossChainOrderHash(order)] = false;

        if (!deposited) {
            // Collect input tokens from user.
            _collectTokensViaPermit2(
                orderKey, permittedAmounts, order.initiateDeadline, order.swapper, witness, witnessTypeString, signature
            );
        }

        emit OrderInitiated(orderHash, msg.sender, fillerData, orderKey);
    }

    //--- Order Resolution Helpers ---//

    /**
     * @notice Prove that an order was filled. Requires that the order oracle exposes
     * a function, isProven(...), that returns true when called with the order details.
     * @dev If an order has configured some additional data that should be executed on
     * initiation, then this has to be provided here as executionData. If the executionData
     * is lost, then the filler should call `modifyOrderFillerdata` to set new executionData.
     * If you are calling this function from an external contract, beaware of re-entry
     * issues from a later execute. (configured of executionData).
     */
    function proveOrderFulfilment(OrderKey calldata orderKey, bytes calldata executionData) external {
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
        _deliverTokens(orderKey.inputs, fillerAddress, governanceFee);

        // Return collateral to the filler. Load the collateral details from the order.
        // (Filler provided collateral).
        address collateralToken = orderKey.collateral.collateralToken;
        uint256 fillerCollateralAmount = orderKey.collateral.fillerCollateralAmount;

        // If the order was challenged, then the challenger also provided collateral. All of this goes to the filler.
        // The below logic relies on the implementation constraint of:
        // orderContext.challenger != address(0) if status == OrderStatus.Challenged
        // This is valid since when `status = OrderStatus.Challenged` is set, right before the challenger's address is
        // also set.
        if (status == OrderStatus.Challenged) {
            // Add collateral amount. Both collaterals were paid in the same tokens.
            // This lets us do only a single transfer call.
            fillerCollateralAmount += orderKey.collateral.challengerCollateralAmount;
        }

        // Pay collateral tokens
        // No need to check if collateralToken is a deployed contract.
        // It has already been entered into our contract & we don't want this call to revert.
        SafeTransferLib.safeTransfer(collateralToken, fillerAddress, fillerCollateralAmount);

        bytes32 identifier = orderContext.identifier;
        if (identifier != bytes32(0)) FillerDataLib.execute(identifier, orderHash, executionData);

        emit OrderProven(orderHash, msg.sender);
    }

    /**
     * @notice Prove that an order was filled. Requires that the order oracle exposes
     * a function, isProven(...), that returns true when called with the order details.
     * @dev Anyone can call this but the payout goes to the filler of the order.
     * If you are calling this function from an external contract, beaware of re-entry
     * issues from a later execute. (configured of executionData).
     */
    function optimisticPayout(OrderKey calldata orderKey, bytes calldata executionData) external {
        bytes32 orderHash = _orderKeyHash(orderKey);
        OrderContext storage orderContext = _orders[orderHash];

        // Check if order is claimed:
        if (orderContext.status != OrderStatus.Claimed) revert WrongOrderStatus(orderContext.status);
        // If OrderStatus != Claimed then it must either be:
        // 1. One of the proved states => we already paid the inputs.
        // 2. Has been challenged (or substate of) => use `completeDispute(...)` or `proveOrderFulfilment(...)`
        // as a result, we shall only continue if orderContext.status == OrderStatus.Claimed.
        orderContext.status = OrderStatus.OptimiscallyFilled;

        // If time is post challenge deadline, then the order can only progress to optimistic payout.
        uint256 challengeDeadline = orderKey.reactorContext.challengeDeadline;
        if (block.timestamp <= challengeDeadline) {
            revert OrderNotReadyForOptimisticPayout(uint32(challengeDeadline));
        }

        address fillerAddress = orderContext.fillerAddress;

        // Pay input tokens to filler.
        _deliverTokens(orderKey.inputs, fillerAddress, governanceFee);

        // Get order collateral.
        address collateralToken = orderKey.collateral.collateralToken;
        uint256 fillerCollateralAmount = orderKey.collateral.fillerCollateralAmount;

        // Pay collateral tokens
        // collateralToken has already been entered so no need to check if
        // it is a valid token.
        SafeTransferLib.safeTransfer(collateralToken, fillerAddress, fillerCollateralAmount);

        bytes32 identifier = orderContext.identifier;
        if (identifier != bytes32(0)) FillerDataLib.execute(identifier, orderHash, executionData);

        emit OptimisticPayout(orderHash);
    }

    //--- Disputes ---//

    /**
     * @notice Disputes a claim. If a claimed order hasn't been delivered post the fill deadline
     * then the order should be challenged. This allows anyone to attempt to claim the collateral
     * the filler provided (at the risk of losing their own collateral).
     * @dev For challengers it is important to properly verify transactions:
     * 1. Local oracle. If the local oracle isn't trusted, the filler may be able
     * to toggle between is verified and not. This makes it possible for the filler to steal
     * the challenger's collateral
     * 2. Remote Oracle. Likewise for the local oracle, remote oracles may be controllable by
     * the filler.
     */
    function dispute(
        OrderKey calldata orderKey
    ) external {
        bytes32 orderKeyHash = _orderKeyHash(orderKey);
        OrderContext storage orderContext = _orders[orderKeyHash];

        // Check if order is claimed and hasn't been challenged:
        if (orderContext.status != OrderStatus.Claimed) revert WrongOrderStatus(orderContext.status);
        // If `orderContext.status != OrderStatus.Claimed` then there are 2 cases:
        // 1. The order hasn't been claimed.
        // 2. We are past the claim state (disputed, proven, etc).
        // As a result, checking if the order has been claimed is enough.

        // Check if challenge deadline hasn't been passed.
        if (uint256(orderKey.reactorContext.challengeDeadline) < block.timestamp) revert ChallengeDeadlinePassed();

        // Later logic relies on  orderContext.challenger != address(0) if orderContext.status = OrderStatus.Challenged.
        // As a result, it is important that this is the only place where these values are set so we can easily audit if
        // the above assertion is true.
        orderContext.challenger = msg.sender;
        orderContext.status = OrderStatus.Challenged;

        // Collect bond collateral.
        // CollateralToken has already been entered so no need to check if it is a valid token.
        SafeTransferLib.safeTransferFrom(
            orderKey.collateral.collateralToken,
            msg.sender,
            address(this),
            orderKey.collateral.challengerCollateralAmount
        );

        emit OrderChallenged(orderKeyHash, msg.sender);
    }

    /**
     * @notice Finalise the dispute.
     */
    function completeDispute(
        OrderKey calldata orderKey
    ) external {
        bytes32 orderKeyHash = _orderKeyHash(orderKey);
        OrderContext storage orderContext = _orders[orderKeyHash];

        // Check if proof deadline has passed. If this is the case (& the order hasn't been proven)
        // it has to be assumed that the order was not filled.
        uint256 proofDeadline = orderKey.reactorContext.proofDeadline;
        if (block.timestamp <= proofDeadline) {
            revert ProofPeriodHasNotPassed(uint32(proofDeadline));
        }

        // Check that the order is currently challenged. If is it currently challenged,
        // it implies that the fulfillment was not proven. Additionally, since the Challenge order status
        // only set together with the challenger address, it must hold that:
        // orderContext.status == OrderStatus.Challenged => orderContext.challenger != address(0).
        if (orderContext.status != OrderStatus.Challenged) revert WrongOrderStatus(orderContext.status);

        // Update the status of the order. This disallows local re-entries.
        // It is important that no external logic is made between the below & above line.
        orderContext.status = OrderStatus.Fraud;

        // Send the input tokens back to the user.
        _deliverTokens(orderKey.inputs, orderKey.swapper, 0);

        unchecked {
            // Divide the collateral between challenger and user. First, get order collateral.
            address collateralToken = orderKey.collateral.collateralToken;
            uint256 fillerCollateralAmount = orderKey.collateral.fillerCollateralAmount;
            uint256 challengerCollateralAmount = orderKey.collateral.challengerCollateralAmount;

            // Send partial collateral back to user
            uint256 swapperCollateralAmount = fillerCollateralAmount / 2;
            // We don't check if collateralToken is a token, since we don't
            // want this call to fail.
            SafeTransferLib.safeTransfer(collateralToken, orderKey.swapper, swapperCollateralAmount);

            // Send the rest to the wallet that called fraud. Similar to the above this should not fail.
            // A: We don't want this to fail.
            // B: If this overflows, it is better than if nothing happened.
            // C: fillerCollateralAmount - swapperCollateralAmount won't overflow as fillerCollateralAmount =
            // swapperCollateralAmount / 2 <= fillerCollateralAmount, = iff fillerCollateralAmount <= 1.
            SafeTransferLib.safeTransfer(
                collateralToken,
                orderContext.challenger,
                challengerCollateralAmount + fillerCollateralAmount - swapperCollateralAmount
            );
        }

        emit FraudAccepted(orderKeyHash);
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
        SafeTransferLib.safeTransferFrom(collateralToken, msg.sender, oldFillerAddress, collateralAmount);

        // Transfer the ERC20 tokens. This requires explicit approval for this contract for each token.
        // This is not done through permit.
        // This function assumes the collection is from msg.sender, as a result we don't need to specify that.
        _collectTokensFromMsgSender(orderKey.inputs, oldFillerAddress, oldOrderPurchaseDiscount);

        // Check if there is an identifier, if there is execute data.
        if (oldIdentifier != bytes32(0)) {
            FillerDataLib.execute(identifier, orderKeyHash, fillerData[fillerDataPointer:]);
        }

        emit OrderPurchased(orderKeyHash, msg.sender);
    }

    /**
     * @dev If some execution data is set that is invalid, this function needs to be used to modify
     * the execution data (identifier) such that the execution data passes.
     * The order cannot be modified if it is considered final.
     */
    function modifyOrderFillerdata(OrderKey calldata orderKey, bytes calldata fillerData) external {
        bytes32 orderKeyHash = _orderKeyHash(orderKey);
        OrderContext storage orderContext = _orders[orderKeyHash];

        // Check that the status isn't final.
        OrderStatus status = orderContext.status;
        if (
            status == OrderStatus.Fraud ||
            status == OrderStatus.OptimiscallyFilled ||
            status == OrderStatus.Proven
        ) revert OrderFinal();

        address currentFiller = orderContext.fillerAddress;

        // This line also disallows modifying non-claimed orders.
        if (currentFiller == address(0) || currentFiller != msg.sender) revert OnlyFiller();

        // Decode filler data.
        (
            address newFillerAddress,
            uint32 newOrderPurchaseDeadline,
            uint16 newOrderPurchaseDiscount,
            bytes32 newIdentifier,
        ) = FillerDataLib.decode(fillerData);

        // Set new storage.
        if (newFillerAddress != currentFiller) orderContext.fillerAddress = newFillerAddress;
        orderContext.orderPurchaseDeadline = newOrderPurchaseDeadline;
        orderContext.orderPurchaseDiscount = newOrderPurchaseDiscount;
        orderContext.identifier = newIdentifier;

        emit OrderPurchaseDetailsModified(orderKeyHash, fillerData);
    }
}
