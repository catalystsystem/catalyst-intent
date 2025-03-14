## Abstract

This specification standardizes intent systems so that components in an intent system can be used composably.

## Specification

The key words “MUST”, “MUST NOT”, “REQUIRED”, “SHALL”, “SHALL NOT”, “SHOULD”, “SHOULD NOT”, “RECOMMENDED”, “MAY”, and “OPTIONAL” in this document are to be interpreted as described in RFC 2119.

### System Design

An intent system contains at least three components:
- **Output Settlement**: Records and specifies how outputs are delivered.
- **Validation**: Validates whether outputs have been delivered through the output settlement.
- **Input Settlement**: Allows for collecting and releasing input tokens.

An intent system built using the above components has data flowing from the Output Settlement to the Validation to the Input Settlement. As a result, the Output Settlement and Validation need to provide interfaces for the subsidiary contracts to read.

### Output Settlement

Compliant Output Settlement contracts MUST implement the `IOutputSettlement` interface to expose whether a list of payloads is valid.

```solidity
interface IOutputSettlement {
    function arePayloadsValid(
        bytes[] calldata payloads
    ) external view returns (bool);
}
```

### Validation

Compliant Validation contracts MUST implement the `IValidation` interface to expose valid payloads collected from other chains.

```solidity
interface IValidation {
    /**
     * @notice Check if some data has been attested to.
     * @param remoteChainId Chain the data originated from.
     * @param remoteOracle Identifier for the remote attestation.
     * @param remoteApplication Identifier for the application that the attestation originated from.
     * @param dataHash Hash of data.
     * @return boolean Whether the data has been attested to.
     */
    function isProven(uint256 remoteChainId, bytes32 remoteOracle, bytes32 remoteApplication, bytes32 dataHash) external view returns (bool);

    /**
     * @notice Check if a series of data has been attested to.
     * @dev More efficient implementation of requireProven. Does not return a boolean; instead, reverts if false.
     * This function returns true if proofSeries is empty.
     * @param proofSeries remoteOracle, remoteChainId, and dataHash encoded in chunks of 32*4=128 bytes.
     */
    function efficientRequireProven(
        bytes calldata proofSeries
    ) external view;
}
```

### Payload Encoding (Optional)

The specification does not specify an encoding for payloads. Output Settlement systems MAY implement or be inspired by the `FillDescription`:

```
Encoded FillDescription
     SOLVER                          0               (32 bytes)
     + ORDERID                       32              (32 bytes)
     + TIMESTAMP                     64              (4 bytes)
     + TOKEN                         68              (32 bytes)
     + AMOUNT                        100             (32 bytes)
     + RECIPIENT                     132             (32 bytes)
     + REMOTE_CALL_LENGTH            164             (2 bytes)
     + REMOTE_CALL                   166             (LENGTH bytes)
     + FULFILLMENT_CONTEXT_LENGTH    166+RC_LENGTH   (2 bytes)
     + FULFILLMENT_CONTEXT           168+RC_LENGTH   (LENGTH bytes)
```

### General Compatibility

`address` variables SHALL be encoded as `bytes32` to be compatible with virtual machines having addresses larger than 20 bytes. This does not make the implementation less efficient.

### Solver Interfaces

This specification does not propose any interface for initiating, solving, or finalizing intents. There are secondary interfaces to facilitate this.

The purpose of this specification is to propose minimal and efficient interfaces for building composable intent protocols and reusing components.

## Security Considerations
