// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { EIP712 } from "solady/utils/EIP712.sol";
import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";

import { CoinFillerWithFee } from "./CoinFillerWithFee.sol";
import { OutputDescription, OutputEncodingLib } from "src/libs/OutputEncodingLib.sol";
import { SignedOutputType } from "./types/SignedOutputType.sol";

/**
 * @dev Solvers use Oracles to pay outputs. This allows us to record the payment.
 * Tokens never touch this contract but goes directly from solver to user.
 */
contract SignedCoinFiller is CoinFillerWithFee, EIP712 {
    error InvalidSigner();

    constructor(
        address owner
    ) payable CoinFillerWithFee(owner) { }

    function _domainNameAndVersion() internal pure virtual override returns (string memory name, string memory version) {
        name = "SignedCompactFiller";
        version = "Signed1";
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparator();
    }

    /**
     * @notice Removed the first 32 bytes of fulfillmentContext, since that is expected to have been
     * prepended by the auction server.
     */
    function _getOutputDescriptionHash(
        OutputDescription calldata outputDescription
    ) internal override pure returns (bytes32 outputHash) {
        bytes calldata remoteCall = outputDescription.remoteCall;
        bytes calldata fulfillmentContext = outputDescription.fulfillmentContext;
        // Check that the length of remoteCall & fulfillmentContext does not exceed type(uint16).max
        if (remoteCall.length > type(uint16).max) revert OutputEncodingLib.RemoteCallOutOfRange();
        if (fulfillmentContext.length > type(uint16).max) revert OutputEncodingLib.FulfillmentContextCallOutOfRange();

        return outputHash = keccak256(abi.encodePacked(
            outputDescription.remoteOracle,
            outputDescription.remoteFiller,
            outputDescription.chainId,
            outputDescription.token,
            outputDescription.amount,
            outputDescription.recipient,
            uint16(remoteCall.length), // To protect against data collisions
            remoteCall,
            uint16(fulfillmentContext.length), // To protect against data collisions
            fulfillmentContext[32:fulfillmentContext.length]
        ));
    }

    function _contextTrueAmount(bytes calldata fulfillmentContext) internal pure returns (uint256 amount) {
        // amount = uint256(bytes32(output.fulfillmentContext[0:32])));
        assembly ("memory-safe") {
            amount := calldataload(add(fulfillmentContext.offset, 0x00))
        }
    }

    function _contextSigner(bytes calldata fulfillmentContext) internal pure returns (address signer) {
        // signer = address(uint160(uint256(bytes32(output.fulfillmentContext[33:65])));
        assembly ("memory-safe") {
            signer := calldataload(add(fulfillmentContext.offset, 0x21))
        }
    }
    
    /**
     * @notice Computes the amount of an order. Allows limit orders and dutch auctions.
     * @dev Uses the fulfillmentContext of the output to determine order type.
     * This contract only understand off-chain auction swaps.
     * Structure:
     * uint256(trueAmount) | bytes1(orderTypeIdentifier) | signer | ......
     * In the actual order, bytes1(orderTypeIdentifier) is the first byte but the order server pre-pends the trueAmount
     */
    function _getAmount(
        OutputDescription calldata output
    ) internal override pure returns (uint256 amount) {
        amount = _contextTrueAmount(output.fulfillmentContext);
        // We don't care about the rest of fulfillmentContext. That is used for off-chain services.
    }

    function _validateSolver(
        OutputDescription calldata output,
        bytes32 solver,
        bytes calldata signature
    ) view internal {
        bytes calldata fulfillmentContext = output.fulfillmentContext;
        uint256 amount = _contextTrueAmount(fulfillmentContext);
        address signer = _contextSigner(fulfillmentContext);

        bytes32 digest = _hashTypedData(SignedOutputType.hashSignedOutput(output, solver, amount));

        bool isValid = SignatureCheckerLib.isValidSignatureNowCalldata(signer, digest, signature);
        if (!isValid) revert InvalidSigner();
    }

    function fill(bytes32 orderId, OutputDescription calldata output, bytes32 proposedSolver, bytes calldata signature) external returns (bytes32) {
        _validateSolver(output, proposedSolver, signature);
        return _fill(orderId, output, proposedSolver);
    }
}
