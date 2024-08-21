// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IOracle } from "../interfaces/IOracle.sol";
import { IOrderType } from "../interfaces/IOrderType.sol";
import {
    CrossChainOrder,
    ISettlementContract,
    Input,
    Output,
    ResolvedCrossChainOrder
} from "../interfaces/ISettlementContract.sol";
import { OrderContext, OrderKey, OrderStatus, OutputDescription, ReactorInfo } from "../interfaces/Structs.sol";

import { CanCollectGovernanceFee } from "../libs/CanCollectGovernanceFee.sol";
import { FillerDataLib } from "../libs/FillerDataLib.sol";
import { IsContractLib } from "../libs/IsContractLib.sol";
import { Permit2Lib } from "../libs/Permit2Lib.sol";

import {
    CannotProveOrder,
    ChallengeDeadlinePassed,
    InitiateDeadlineAfterFill,
    InitiateDeadlinePassed,
    InvalidDeadlineOrder,
    LengthsNotEqual,
    NonceClaimed,
    NotOracle,
    OnlyFiller,
    OrderAlreadyChallenged,
    OrderAlreadyClaimed,
    OrderNotReadyForOptimisticPayout,
    ProofPeriodHasNotPassed,
    PurchaseTimePassed,
    WrongOrderStatus,
    BackupOnlyCallableByFiller
} from "../interfaces/Errors.sol";
import {
    FraudAccepted,
    OptimisticPayout,
    OrderChallenged,
    OrderClaimed,
    OrderProven,
    OrderPurchaseDetailsModified,
    OrderPurchased,
    OrderVerify
} from "../interfaces/Events.sol";

/**
 * @title Base Cross-chain intent Reactor
 * @notice Cross-chain intent resolver. Implements core logic that is shared between all
 * reactors like: Token collection, order interfaces, order resolution:
 * - Optimistic Payout: Orders are assumed to have been filled correctly by the solver if not disputed.
 * - Order Dispute: Orders can be disputed such that proof of fillment has to be made.
 * - Oracle Interfaction: To provide the relevant proofs against order disputes.
 *
 * It is expected that proper order reactors implement:
 * - `_initiate`. To convert partially structured orders into order keys that describe fulfillment conditions.
 * - `_resolveKey`. Helper function to convert an order into an order key.
 * @dev Important implementation quirks:
 * **Token Trust**
 * There is a lot of trust put into the tokens that interact with the contract. Not trust as in the tokens can
 * impact this contract but trust as in a faulty / malicious token may be able to break the order status flow
 * and prevent proper delivery of inputs (to solver) and return of collateral.
 * As a result, it is important that users are aware of the following usage restrictions:
 * 1. Don't use a pausable/blacklist token if there is a risk of one of the actors (user / solver)
 * being paused. This also applies from the user's perspective, if a pausable token is used for
 * collateral their inputs may not be returnable.
 * 2. All inputs have to be trusted by all parties. If one input is unable to be transferred, the whole lot
 * becomes stuck until the issue is resolved.
 * 3. Solvers should validate that they can fill the outputs otherwise their collateral may be at risk and it could annoy users.
 */
abstract contract BaseReactor is CanCollectGovernanceFee, ISettlementContract {
    using Permit2Lib for OrderKey;

    ISignatureTransfer public immutable PERMIT2;

    bytes32 public constant VERSION_FLAGS = bytes32(uint256(1));

    /**
     * @notice Maps an orderkey hash to the relevant orderContext.
     */
    mapping(bytes32 orderKeyHash => OrderContext orderContext) internal _orders;

    constructor(address permit2, address owner) CanCollectGovernanceFee(owner) {
        PERMIT2 = ISignatureTransfer(permit2);
    }

    //--- Expose Storage ---//

    function _orderKeyHash(OrderKey memory orderKey) internal pure returns (bytes32 orderKeyHash) {
        return orderKeyHash = keccak256(abi.encode(orderKey)); // TODO: Is it more efficient to do this manually?
    }

    function getOrderKeyHash(OrderKey calldata orderKey) external pure returns (bytes32 orderKeyHash) {
        return orderKeyHash = _orderKeyHash(orderKey);
    }

    function getOrderContext(OrderKey calldata orderKey) external view returns (OrderContext memory orderContext) {
        return orderContext = _orders[_orderKeyHash(orderKey)];
    }

    //--- Override for implementation ---//

    /**
     * @notice Reactor Order implementations needs to implement this function to initiate their orders.
     * Return an orderKey with the relevant information to solve for.
     * @dev This function shouldn't check if the signature is correct but instead return information
     * to be used by _collectTokensViaPermit2 to verify the order (through PERMIT2).
     */
    function _initiate(
        CrossChainOrder calldata order,
        bytes calldata fillerData
    ) internal virtual returns (OrderKey memory orderKey, bytes32 witness, string memory witnessTypeString);

    /**
     * @notice Logic function for resolveKey(...).
     * @dev Order implementations of this reactor are required to implement this function.
     */
    function _resolveKey(
        CrossChainOrder calldata order,
        bytes calldata fillerData
    ) internal view virtual returns (OrderKey memory);

    /**
     * @notice Resolves a specific CrossChainOrder into a Catalyst specific OrderKey.
     * @dev This provides a more precise description of the cost of the order compared to the generic resolve(...).
     * @param order CrossChainOrder to resolve.
     * @param fillerData Any filler-defined data required by the settler
     * @return orderKey The full description of the order, including the inputs and outputs of the order
     */
    function resolveKey(
        CrossChainOrder calldata order,
        bytes calldata fillerData
    ) external view returns (OrderKey memory orderKey) {
        return orderKey = _resolveKey(order, fillerData);
    }

    //--- Token Handling ---//

    /**
     * @notice Multi purpose order flow function that:
     * - Orders the collection of tokens. This includes checking if the user has enough & approval.
     * - Verification of the signature for the order. This ensures the user has accepted the order conditions.
     * - Spend nonces. Disallow the same order from being claimed twice.  // TODO <- Check
     */
    function _collectTokensViaPermit2(
        OrderKey memory orderKey,
        address owner,
        bytes32 witness,
        string memory witnessTypeString,
        bytes calldata signature
    ) internal virtual {
        (
            ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,
            ISignatureTransfer.SignatureTransferDetails[] memory transferDetails
        ) = orderKey.toPermit(address(this));

        PERMIT2.permitWitnessTransferFrom(permitBatch, transferDetails, owner, witness, witnessTypeString, signature);
    }

    /**
     * @notice Collects tokens without permit2.
     * @dev Can only be used to collect tokens from msg.sender.
     * If inputs[i].amount * discount overflows the amount is set to inputs[i].amount.
     * @param inputs Tokens to collect from msg.sender.
     * @param to Destination address for the collected tokens. To collect to this contract, set address(this).
     */
    function _collectTokensFromMsgSender(Input[] calldata inputs, address to, uint16 discount) internal virtual {
        address from = msg.sender;
        uint256 numInputs = inputs.length;
        unchecked {
            for (uint256 i = 0; i < numInputs; ++i) {
                Input calldata input = inputs[i];
                address token = input.token;
                uint256 amount = input.amount;
                // If discount == 0, then set amount to amount.
                // If the discount subtraction overflows, also set the amount to amount.
                // Otherwise, compute the discount as: amount - (amount * uint256(discount)) / uint256(type(uint16).max)
                amount = (discount != 0 && amount < type(uint256).max / uint256(discount))
                    ? amount - (amount * uint256(discount)) / uint256(type(uint16).max)
                    : amount;
                // Inputs have already been collected before. No need to verify if these are actual tokens.
                SafeTransferLib.safeTransferFrom(token, from, to, amount);
            }
        }
    }

    /**
     * @notice Sends a list of inputs to the target address.
     * @dev This function can be used for paying the filler or refunding the user in case of disputes.
     * @param inputs List of inputs that are to be paid.
     * @param to Destination address.
     */
    function _deliverInputs(Input[] calldata inputs, address to, uint256 fee) internal virtual {
        // Read governance fee.
        uint256 numInputs = inputs.length;
        for (uint256 i; i < numInputs; ++i) {
            Input calldata input = inputs[i];
            address token = input.token;
            // Collect governance fee. Importantly, this also sets the value as collected.
            uint256 amount = input.amount;
            amount = fee == 0 ? amount : _collectGovernanceFee(token, amount, fee);
            // We don't need to check if token is deployed since we
            // got here. Reverting here would also freeze collateral.
            SafeTransferLib.safeTransfer(token, to, amount);
        }
    }

    //--- Order Handling ---//

    /**
     * @notice Initiates a cross-chain order
     * @dev Called by the filler.
     * When a filler initiates a transaction it is important that they do the following:
     * 1. Trust the reactor. Technically, anyone can deploy a reactor that takes these interfaces.
     * As the filler has to provide collateral, this collateral could be at risk.
     * 2. Verify that the deadlines provided in the order are sane. If proof - challenge is small
     * then it may impossible to prove thus free to challenge.
     * 3. Trust the oracles. Any oracles can be provided but they may not signal that the proof
     * is or isn't valid.
     * 4. Verify all inputs & outputs. If they contain a token the filler does not trust, do not claim the order.
     * It may cause a host of problem but most importantly: Inability to payout inputs & Inability to payout collateral.
     * @param order The CrossChainOrder definition
     * @param signature The end user signature for the order
     * @param fillerData Any filler-defined data required by the settler
     */
    function initiate(
        CrossChainOrder calldata order,
        bytes calldata signature,
        bytes calldata fillerData
    ) external returns (OrderKey memory orderKey) {
        // The order initiation must be less than the fill deadline. Both of them cannot be the current time as well.
        // Fill deadline must be after initiate deadline. Otherwise the solver is prone to making a mistake.
        if (order.fillDeadline < order.initiateDeadline) {
            revert InitiateDeadlineAfterFill();
        }

        // Check if initiate Deadline has passed.
        if (order.initiateDeadline < block.timestamp) {
            revert InitiateDeadlinePassed();
        }
        // Notice that the 2 above checks also check if order.fillDeadline < block.timestamp since
        // (order.fillDeadline < order.initiateDeadline) & (order.initiateDeadline < block.timestamp)
        // => order.fillDeadline < block.timestamp is disallowed.

        // Decode filler data.
        (address fillerAddress, uint32 orderPurchaseDeadline, uint16 orderDiscount, bytes32 identifier, uint256 fillerDataPointer) =
            FillerDataLib.decode(fillerData);

        // Initiate order.
        bytes32 witness;
        string memory witnessTypeString;
        (orderKey, witness, witnessTypeString) = _initiate(order, fillerData[fillerDataPointer:]);

        // The proof deadline should be the last deadline and it must be after the challenge deadline.
        // The challenger should be able to challenge after the order is filled.
        ReactorInfo memory reactorInfo = orderKey.reactorContext;
        // Check if order.fillDeadline < reactorInfo.challengeDeadline && reactorInfo.challengeDeadline < reactorInfo.proofDeadline.
        // So if order.fillDeadline >= reactorInfo.challengeDeadline || reactorInfo.challengeDeadline >= reactorInfo.proofDeadline
        // then the deadlines are invalid.
        if (
            order.fillDeadline >= reactorInfo.challengeDeadline
                || reactorInfo.challengeDeadline >= reactorInfo.proofDeadline
        ) {
            revert InvalidDeadlineOrder();
        }

        // Check that the order hasn't been claimed yet. We will then set the order status
        // so other can't claim it. This acts as a local reentry check.
        OrderContext storage orderContext = _orders[_orderKeyHash(orderKey)];
        if (orderContext.status != OrderStatus.Unfilled) revert OrderAlreadyClaimed(orderContext.status);
        orderContext.status = OrderStatus.Claimed; // Now this order cannot be claimed again.
        orderContext.fillerAddress = fillerAddress;
        orderContext.orderPurchaseDeadline = orderPurchaseDeadline;
        orderContext.orderDiscount = orderDiscount;
        orderContext.initTimestamp = uint32(block.timestamp);
        if (identifier != bytes32(0)) orderContext.identifier = identifier;

        // Check first if it is not an EOA or undeployed contract because SafeTransferLib does not revert in this case.
        IsContractLib.checkCodeSize(orderKey.collateral.collateralToken);
        // Collateral is collected from sender instead of fillerAddress.
        // TODO: Maybe store another collateral refund address?
        SafeTransferLib.safeTransferFrom(
            orderKey.collateral.collateralToken, msg.sender, address(this), orderKey.collateral.fillerCollateralAmount
        );

        // Collect input tokens from user.
        _collectTokensViaPermit2(orderKey, order.swapper, witness, witnessTypeString, signature);
    }

    /**
     * @notice Resolves an order into an ERC-7683 compatible order struct.
     * By default relies on _resolveKey to convert OrderKey into a ResolvedCrossChainOrder
     * @dev Can be overwritten if there isn't a translation of an orderKey into resolvedOrder.
     * @param order CrossChainOrder to resolve.
     * @param  fillerData Any filler-defined data required by the settler
     * @return resolvedOrder ERC-7683 compatible order description, including the inputs and outputs of the order
     */
    function _resolve(
        CrossChainOrder calldata order,
        bytes calldata fillerData
    ) internal view virtual returns (ResolvedCrossChainOrder memory resolvedOrder) {
        OrderKey memory orderKey = _resolveKey(order, fillerData);
        (address fillerAddress,,,,) = FillerDataLib.decode(fillerData);

        // Inputs can be taken directly from the orderKey.
        Input[] memory swapperInputs = orderKey.inputs;
        // Likewise for outputs.

        uint256 numOutputs = orderKey.outputs.length;
        Output[] memory swapperOutputs = new Output[](numOutputs);
        for (uint256 i = 0; i < numOutputs; ++i) {
            OutputDescription memory catalystOutput = orderKey.outputs[i];
            swapperOutputs[i] = Output({
                token: catalystOutput.token,
                amount: catalystOutput.amount,
                recipient: catalystOutput.recipient,
                chainId: catalystOutput.chainId
            });
        }

        // fillerOutputs are of the Output type and as a result, we can't just
        // load swapperInputs into fillerOutputs. As a result, we need to parse
        // the individual inputs and make a new struct.
        uint256 _governanceFee = governanceFee;
        uint256 numInputs = swapperInputs.length;
        Output[] memory fillerOutputs = new Output[](numInputs);
        Output memory fillerOutput;
        for (uint256 i; i < numInputs; ++i) {
            Input memory input = swapperInputs[i];
            fillerOutput = Output({
                token: bytes32(uint256(uint160(input.token))),
                amount: _amountLessfee(input.amount, _governanceFee),
                recipient: bytes32(uint256(uint160(fillerAddress))),
                chainId: uint32(block.chainid)
            });
            fillerOutputs[i] = fillerOutput;
        }

        // Lastly, complete the ResolvedCrossChainOrder struct.
        resolvedOrder = ResolvedCrossChainOrder({
            settlementContract: order.settlementContract,
            swapper: order.swapper,
            nonce: order.nonce,
            originChainId: order.originChainId,
            initiateDeadline: order.initiateDeadline,
            fillDeadline: order.fillDeadline,
            swapperInputs: swapperInputs,
            swapperOutputs: swapperOutputs,
            fillerOutputs: fillerOutputs
        });
    }

    /**
     * @notice ERC-7683: Resolves a specific CrossChainOrder into a generic ResolvedCrossChainOrder
     * @dev Intended to improve standardized integration of various order types and settlement contracts
     * @param order CrossChainOrder to resolve.
     * @param fillerData Any filler-defined data required by the settler
     * @return resolvedOrder ERC-7683 compatible order description, including the inputs and outputs of the order
     */
    function resolve(
        CrossChainOrder calldata order,
        bytes calldata fillerData
    ) external view returns (ResolvedCrossChainOrder memory resolvedOrder) {
        return _resolve(order, fillerData);
    }

    //--- Order Purchase Helpers ---//

    /**
     * @notice This function is called from whoever wants to buy an order from a filler and gain a reward
     * @dev If you are buying a challenged order, ensure that you have sufficient time to prove the order or
     * your funds may be at risk.
     * Set newPurchaseDeadline in the past to disallow future takeovers.
     * @param orderKey Claimed order to be purchased from the filler
     * @param fillerData New filler data
     */
    function purchaseOrder(OrderKey calldata orderKey, bytes calldata fillerData) external {
        bytes32 orderKeyHash = _orderKeyHash(orderKey);
        OrderContext storage orderContext = _orders[orderKeyHash];

        OrderStatus status = orderContext.status;

        // The order should have been claimed and not paid / proven / fraud proven (inputs should be intact)
        // for it to be purchased.
        if (status != OrderStatus.Claimed && status != OrderStatus.Challenged) {
            revert WrongOrderStatus(orderContext.status);
        }

        // The order cannot be purchased after the max time specified to be sold at has passed
        if (orderContext.orderPurchaseDeadline < block.timestamp) {
            revert PurchaseTimePassed();
        }

        // Decode filler data.
        (address fillerAddress, uint32 orderPurchaseDeadline, uint16 orderDiscount, bytes32 identifier, uint256 fillerDataPointer) = FillerDataLib.decode(fillerData);

        // Load old storage variables.
        address oldFillerAddress = orderContext.fillerAddress;
        uint16 oldOrderDiscount = orderContext.orderDiscount;

        // We can now update the storage with the new filler data.
        // This allows us to avoid reentry protecting this function.
        orderContext.fillerAddress = fillerAddress;
        orderContext.orderPurchaseDeadline = orderPurchaseDeadline;
        orderContext.orderDiscount = orderDiscount;
        if (identifier != bytes32(0)) orderContext.identifier = identifier;

        // We can now make external calls without it impacting reentring into this call.

        // Collateral is paid for in full.
        address collateralToken = orderKey.collateral.collateralToken;
        uint256 collateralAmount = orderKey.collateral.fillerCollateralAmount;
        // No need to check if collateral is valid, since it has already entered the contract.
        SafeTransferLib.safeTransferFrom(collateralToken, msg.sender, oldFillerAddress, collateralAmount);

        // Transfer the ERC20 tokens. This requires explicit approval for this contract for each token. This is not done through permit.
        // This function assumes the collection is from msg.sender, as a result we don't need to specify that.
        _collectTokensFromMsgSender(orderKey.inputs, oldFillerAddress, oldOrderDiscount);

        // Check if there is an identifier, if there is execute data.
        if (identifier != bytes32(0)) FillerDataLib.execute(identifier, orderKeyHash, fillerData[fillerDataPointer:]);

        emit OrderPurchased(orderKeyHash, msg.sender);
    }

    function modifyBuyableOrder(
        OrderKey calldata orderKey,
        bytes calldata fillerData
    ) external {
        bytes32 orderKeyHash = _orderKeyHash(orderKey);
        OrderContext storage orderContext = _orders[orderKeyHash];

        address filler = orderContext.fillerAddress;

        // This line also disallows modifying non-claimed orders.
        if (filler == address(0) || filler != msg.sender) revert OnlyFiller();

        // Decode filler data.
        (address fillerAddress, uint32 orderPurchaseDeadline, uint16 orderDiscount, bytes32 identifier, ) = FillerDataLib.decode(fillerData);

        // Set new storage.
        if (fillerAddress != filler) orderContext.fillerAddress = fillerAddress;
        orderContext.orderPurchaseDeadline = orderPurchaseDeadline;
        orderContext.orderDiscount = orderDiscount;
        if (identifier != orderContext.identifier) orderContext.identifier = identifier;

        emit OrderPurchaseDetailsModified(orderKeyHash, fillerAddress, orderPurchaseDeadline, orderDiscount, identifier);
    }

    //--- Order Resolution Helpers ---//

    /**
     * @notice Prove that an order was filled. Requires that the order oracle exposes
     * a function, isProven(...), that returns true when called with the order details.
     * @dev
     */
    function _proveOrderFulfillment(OrderKey calldata orderKey, OrderContext storage orderContext) internal {
        OrderStatus status = orderContext.status;
        address fillerAddress = orderContext.fillerAddress;

        // Only allow processing if order status is either claimed or challenged
        if (status != OrderStatus.Claimed && status != OrderStatus.Challenged) {
            revert WrongOrderStatus(orderContext.status);
        }
        // Immediately set order status to filled. If the order hasn't been filled
        // then the next line will fail. This acts as a LOCAL reentry check.
        orderContext.status = OrderStatus.Filled;

        // The following call is a external call to an untrusted contract. As a result,
        // it is important that we protect this contract against reentry calls, even if read-only.
        if (!IOracle(orderKey.localOracle).isProven(orderKey.outputs, orderKey.reactorContext.fillByDeadline)) {
            revert CannotProveOrder();
        }

        // Payout input.
        _deliverInputs(orderKey.inputs, fillerAddress, governanceFee);

        // Return collateral to the filler. Load the collateral details from the order.
        // (Filler provided collateral).
        address collateralToken = orderKey.collateral.collateralToken;
        uint256 fillerCollateralAmount = orderKey.collateral.fillerCollateralAmount;

        // If the order was challenged, then the challenger also provided collateral. All of this goes to the filler.
        // The below logic relies on the implementation constraint of:
        // orderContext.challenger != address(0) if status == OrderStatus.Challenged
        // This is valid since when `status = OrderStatus.Challenged` is set, right before the challenger's address is also set.
        if (status == OrderStatus.Challenged) {
            // Add collateral amount. Both collaterals were paid in the same tokens.
            // This lets us do only a single transfer call.
            fillerCollateralAmount += orderKey.collateral.challengerCollateralAmount;
        }

        // Pay collateral tokens
        // No need to check if collateralToken is a deployed contract.
        // It has already been entered into our contract.
        SafeTransferLib.safeTransfer(collateralToken, fillerAddress, fillerCollateralAmount);
    }

    /**
     * @notice Prove that an order was filled. Requires that the order oracle exposes
     * a function, isProven(...), that returns true when called with the order details.
     * @dev
     */
    function proveOrderFulfillment(OrderKey calldata orderKey, bytes calldata executionData) external {
        bytes32 orderHash = _orderKeyHash(orderKey);
        OrderContext storage orderContext = _orders[orderHash];

        _proveOrderFulfillment(orderKey, orderContext);

        bytes32 identifier = orderContext.identifier;
        if (identifier != bytes32(0)) FillerDataLib.execute(identifier, orderHash, executionData);

        emit OrderProven(orderHash, msg.sender);
    }

    /**
     * @notice Collect the order result
     * @dev Anyone can call this but the payout goes to the filler of the order.
     */
    function _optimisticPayout(OrderKey calldata orderKey, OrderContext storage orderContext) internal {
        // Check if order is claimed:
        if (orderContext.status != OrderStatus.Claimed) revert WrongOrderStatus(orderContext.status);
        // If OrderStatus != Claimed then it must either be:
        // 1. One of the proved states => we already paid the inputs.
        // 2. Has been challenged (or substate of) => use `completeDispute(...)` or `proveOrderFulfillment(...)`
        // as a result, checking only we shall only continue if orderContext.status == OrderStatus.Claimed.
        orderContext.status = OrderStatus.OPFilled;

        // If time is post challenge deadline, then the order can only progress to optimistic payout.
        uint256 challengeDeadline = orderKey.reactorContext.challengeDeadline;
        if (block.timestamp <= challengeDeadline) {
            unchecked {
                revert OrderNotReadyForOptimisticPayout(uint32(challengeDeadline - block.timestamp + 1));
            }
        }

        address fillerAddress = orderContext.fillerAddress;

        // Pay input tokens to filler.
        _deliverInputs(orderKey.inputs, fillerAddress, governanceFee);

        // Get order collateral.
        address collateralToken = orderKey.collateral.collateralToken;
        uint256 fillerCollateralAmount = orderKey.collateral.fillerCollateralAmount;

        // Pay collateral tokens
        // collateralToken has already been entered so no need to check if
        // it is a valid token.
        SafeTransferLib.safeTransfer(collateralToken, fillerAddress, fillerCollateralAmount);
    }

    function optimisticPayout(OrderKey calldata orderKey, bytes calldata executionData) external {
        bytes32 orderHash = _orderKeyHash(orderKey);
        OrderContext storage orderContext = _orders[orderHash];

        _optimisticPayout(orderKey, orderContext);

        bytes32 identifier = orderContext.identifier;
        if (identifier != bytes32(0)) FillerDataLib.execute(identifier, orderHash, executionData);

        emit OrderProven(orderHash, msg.sender);
    }

    //-- Order Resolution Backups --//


    function proveOrderFulfillmentBackup(OrderKey calldata orderKey, address backupFiller) external {
        bytes32 orderHash = _orderKeyHash(orderKey);
        OrderContext storage orderContext = _orders[orderHash];

        address fillerAddress = orderContext.fillerAddress;
        if (msg.sender != fillerAddress) revert BackupOnlyCallableByFiller(fillerAddress, msg.sender);
        // Allow sending the outputs to another address. This is important if the lgoic for the
        // normal execution would leave the funds vulnurable.
        orderContext.fillerAddress = backupFiller;

        _proveOrderFulfillment(orderKey, orderContext);

        emit OptimisticPayout(orderHash);
    }


    function optimisticPayoutBackup(OrderKey calldata orderKey, address backupFiller) external {
        bytes32 orderHash = _orderKeyHash(orderKey);
        OrderContext storage orderContext = _orders[orderHash];

        address fillerAddress = orderContext.fillerAddress;
        if (msg.sender != fillerAddress) revert BackupOnlyCallableByFiller(fillerAddress, msg.sender);
        // Allow sending the outputs to another address. This is important if the lgoic for the
        // normal execution would leave the funds vulnurable.
        orderContext.fillerAddress = backupFiller;

        _optimisticPayout(orderKey, orderContext);

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
     * TODO: Are there more risks?
     */
    function dispute(OrderKey calldata orderKey) external {
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
        // collateralToken has already been entered so no need to check if
        // it is a valid token.
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
    function completeDispute(OrderKey calldata orderKey) external {
        bytes32 orderKeyHash = _orderKeyHash(orderKey);
        OrderContext storage orderContext = _orders[orderKeyHash];

        // Check if proof deadline has passed. If this is the case, (& the order hasn't been proven)
        // it has to be assumed that the order was not filled.
        uint256 proofDeadline = orderKey.reactorContext.proofDeadline;
        if (block.timestamp <= proofDeadline) {
            unchecked {
                revert ProofPeriodHasNotPassed(uint32(proofDeadline - block.timestamp + 1));
            }
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
        _deliverInputs(orderKey.inputs, orderKey.swapper, 0);
        // Divide the collateral between challenger and user. // TODO: figure out ration to each.
        // Get order collateral.
        address collateralToken = orderKey.collateral.collateralToken;
        uint256 fillerCollateralAmount = orderKey.collateral.fillerCollateralAmount;
        uint256 challengerCollateralAmount = orderKey.collateral.challengerCollateralAmount;

        unchecked {
            // Send partial collateral back to user
            uint256 swapperCollateralAmount = fillerCollateralAmount / 2;
            // We don't check if collateralToken is a token, since we don't
            // want this call to fail.
            SafeTransferLib.safeTransfer(collateralToken, orderKey.swapper, swapperCollateralAmount);

            // Send the rest to the wallet that proof fraud:
            // Similar to the above. We don't want this to fail.

            // A: We don't want this to fail.
            // B: If this overflows, it is better than if nothing happened.
            // C: fillerCollateralAmount - swapperCollateralAmount won't overflow as fillerCollateralAmount = swapperCollateralAmount / 2.
            SafeTransferLib.safeTransfer(
                collateralToken,
                orderContext.challenger,
                challengerCollateralAmount + fillerCollateralAmount - swapperCollateralAmount
            );
        }

        emit FraudAccepted(orderKeyHash);
    }
}
