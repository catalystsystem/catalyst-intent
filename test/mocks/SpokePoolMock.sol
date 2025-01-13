// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./V3SpokePoolInterface.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

abstract contract SpokePoolMock is V3SpokePoolInterface {

    // Count of deposits is used to construct a unique deposit identifier for this spoke pool.
    uint32 public numberOfDeposits;

    constructor() {}

    /********************************************
     *            DEPOSITOR FUNCTIONS           *
     ********************************************/

    /**
     * @notice Previously, this function allowed the caller to specify the exclusivityDeadline, otherwise known as the
     * as exact timestamp on the destination chain before which only the exclusiveRelayer could fill the deposit. Now,
     * the caller is expected to pass in an exclusivityPeriod which is the number of seconds to be added to the
     * block.timestamp to produce the exclusivityDeadline. This allows the caller to ignore any latency associated
     * with this transaction being mined and propagating this transaction to the miner.
     * @notice Request to bridge input token cross chain to a destination chain and receive a specified amount
     * of output tokens. The fee paid to relayers and the system should be captured in the spread between output
     * amount and input amount when adjusted to be denominated in the input token. A relayer on the destination
     * chain will send outputAmount of outputTokens to the recipient and receive inputTokens on a repayment
     * chain of their choice. Therefore, the fee should account for destination fee transaction costs,
     * the relayer's opportunity cost of capital while they wait to be refunded following an optimistic challenge
     * window in the HubPool, and the system fee that they'll be charged.
     * @dev On the destination chain, the hash of the deposit data will be used to uniquely identify this deposit, so
     * modifying any params in it will result in a different hash and a different deposit. The hash will comprise
     * all parameters to this function along with this chain's chainId(). Relayers are only refunded for filling
     * deposits with deposit hashes that map exactly to the one emitted by this contract.
     * @param depositor The account credited with the deposit who can request to "speed up" this deposit by modifying
     * the output amount, recipient, and message.
     * @param recipient The account receiving funds on the destination chain. Can be an EOA or a contract. If
     * the output token is the wrapped native token for the chain, then the recipient will receive native token if
     * an EOA or wrapped native token if a contract.
     * @param inputToken The token pulled from the caller's account and locked into this contract to
     * initiate the deposit. The equivalent of this token on the relayer's repayment chain of choice will be sent
     * as a refund. If this is equal to the wrapped native token then the caller can optionally pass in native token as
     * msg.value, as long as msg.value = inputTokenAmount.
     * @param outputToken The token that the relayer will send to the recipient on the destination chain. Must be an
     * ERC20.
     * @param inputAmount The amount of input tokens to pull from the caller's account and lock into this contract.
     * This amount will be sent to the relayer on their repayment chain of choice as a refund following an optimistic
     * challenge window in the HubPool, less a system fee.
     * @param outputAmount The amount of output tokens that the relayer will send to the recipient on the destination.
     * @param destinationChainId The destination chain identifier. Must be enabled along with the input token
     * as a valid deposit route from this spoke pool or this transaction will revert.
     * @param exclusiveRelayer The relayer that will be exclusively allowed to fill this deposit before the
     * exclusivity deadline timestamp. This must be a valid, non-zero address if the exclusivity deadline is
     * greater than the current block.timestamp. If the exclusivity deadline is < currentTime, then this must be
     * address(0), and vice versa if this is address(0).
     * @param quoteTimestamp The HubPool timestamp that is used to determine the system fee paid by the depositor.
     *  This must be set to some time between [currentTime - depositQuoteTimeBuffer, currentTime]
     * where currentTime is block.timestamp on this chain or this transaction will revert.
     * @param fillDeadline The deadline for the relayer to fill the deposit. After this destination chain timestamp,
     * the fill will revert on the destination chain. Must be set between [currentTime, currentTime + fillDeadlineBuffer]
     * where currentTime is block.timestamp on this chain or this transaction will revert.
     * @param exclusivityPeriod Added to the current time to set the exclusive relayer deadline,
     * which is the deadline for the exclusiveRelayer to fill the deposit. After this destination chain timestamp,
     * anyone can fill the deposit.
     * @param message The message to send to the recipient on the destination chain if the recipient is a contract.
     * If the message is not empty, the recipient contract must implement handleV3AcrossMessage() or the fill will revert.
     */
    function depositV3(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityPeriod,
        bytes calldata message
    ) public payable override {
        // slither-disable-next-line timestamp
        uint256 currentTime = getCurrentTime();

        // msg.value should be 0 if input token isn't the wrapped native token.
        if (msg.value != 0) revert MsgValueDoesNotMatchInputAmount();
        SafeTransferLib.safeTransferFrom(inputToken, msg.sender, address(this), inputAmount);

        emit V3FundsDeposited(
            inputToken,
            outputToken,
            inputAmount,
            outputAmount,
            destinationChainId,
            // Increment count of deposits so that deposit ID for this spoke pool is unique.
            numberOfDeposits++,
            quoteTimestamp,
            fillDeadline,
            uint32(currentTime) + exclusivityPeriod,
            depositor,
            recipient,
            exclusiveRelayer,
            message
        );
    }

    /**
     * @notice Submits deposit and sets quoteTimestamp to current Time. Sets fill and exclusivity
     * deadlines as offsets added to the current time. This function is designed to be called by users
     * such as Multisig contracts who do not have certainty when their transaction will mine.
     * @param depositor The account credited with the deposit who can request to "speed up" this deposit by modifying
     * the output amount, recipient, and message.
     * @param recipient The account receiving funds on the destination chain. Can be an EOA or a contract. If
     * the output token is the wrapped native token for the chain, then the recipient will receive native token if
     * an EOA or wrapped native token if a contract.
     * @param inputToken The token pulled from the caller's account and locked into this contract to
     * initiate the deposit. The equivalent of this token on the relayer's repayment chain of choice will be sent
     * as a refund. If this is equal to the wrapped native token then the caller can optionally pass in native token as
     * msg.value, as long as msg.value = inputTokenAmount.
     * @param outputToken The token that the relayer will send to the recipient on the destination chain. Must be an
     * ERC20.
     * @param inputAmount The amount of input tokens to pull from the caller's account and lock into this contract.
     * This amount will be sent to the relayer on their repayment chain of choice as a refund following an optimistic
     * challenge window in the HubPool, plus a system fee.
     * @param outputAmount The amount of output tokens that the relayer will send to the recipient on the destination.
     * @param destinationChainId The destination chain identifier. Must be enabled along with the input token
     * as a valid deposit route from this spoke pool or this transaction will revert.
     * @param exclusiveRelayer The relayer that will be exclusively allowed to fill this deposit before the
     * exclusivity deadline timestamp.
     * @param fillDeadlineOffset Added to the current time to set the fill deadline, which is the deadline for the
     * relayer to fill the deposit. After this destination chain timestamp, the fill will revert on the
     * destination chain.
     * @param exclusivityPeriod Added to the current time to set the exclusive relayer deadline,
     * which is the deadline for the exclusiveRelayer to fill the deposit. After this destination chain timestamp,
     * anyone can fill the deposit up to the fillDeadline timestamp.
     * @param message The message to send to the recipient on the destination chain if the recipient is a contract.
     * If the message is not empty, the recipient contract must implement handleV3AcrossMessage() or the fill will revert.
     */
    function depositV3Now(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address exclusiveRelayer,
        uint32 fillDeadlineOffset,
        uint32 exclusivityPeriod,
        bytes calldata message
    ) external payable {
        depositV3(
            depositor,
            recipient,
            inputToken,
            outputToken,
            inputAmount,
            outputAmount,
            destinationChainId,
            exclusiveRelayer,
            uint32(getCurrentTime()),
            uint32(getCurrentTime()) + fillDeadlineOffset,
            exclusivityPeriod,
            message
        );
    }

    /**************************************
     *           VIEW FUNCTIONS           *
     **************************************/

    /**
     * @notice Returns chain ID for this network.
     * @dev Some L2s like ZKSync don't support the CHAIN_ID opcode so we allow the implementer to override this.
     */
    function chainId() public view virtual returns (uint256) {
        return block.chainid;
    }

    /**
     * @notice Gets the current time.
     * @return uint for the current timestamp.
     */
    function getCurrentTime() public view virtual returns (uint256) {
        return block.timestamp; // solhint-disable-line not-rely-on-time
    }

    // Added to enable the this contract to receive native token (ETH). Used when unwrapping wrappedNativeToken.
    receive() external payable {}

    // Reserve storage slots for future versions of this base contract to add state variables without
    // affecting the storage layout of child contracts. Decrement the size of __gap whenever state variables
    // are added. This is at bottom of contract to make sure it's always at the end of storage.
    uint256[999] private __gap;
}