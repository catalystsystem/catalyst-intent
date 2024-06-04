// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BitcoinOpcodes.sol";
import { AddressType, BitcoinAddress } from "../interfaces/Structs.sol";

/**
 * @notice This contract implement helper functions for external actors
 * when they encode or decode Bitcoin scripts.
 * @dev This contract is not intended for on-chain calls.
 */
library BtcScript {
    //--- Bitcoin Script Decode Helpers ---//

    /**
     * @notice Global helper for decoding Bitcoin addresses
     */
    function getBitcoinAddress(bytes calldata script) internal pure returns (BitcoinAddress memory btcAddress) {
        // Check if P2PKH
        bytes1 firstByte = script[0];
        if (firstByte == OP_DUB) {
            if (script.length == P2PKH_SCRIPT_LENGTH) {
                btcAddress.addressType = AddressType.P2PKH;
                btcAddress.implementationHash = decodeP2PKH(script);
                return btcAddress;
            }
        } else if (firstByte == OP_HASH160) {
            if (script.length == P2SH_SCRIPT_LENGTH) {
                btcAddress.addressType = AddressType.P2SH;
                btcAddress.implementationHash = decodeP2SH(script);
                return btcAddress;
            }
        } else {
            // This is likely a segwit transaction. Try decoding the witness program
            (int8 version, uint8 witnessLength, bytes32 witPro) = decodeWitnessProgram(script);
            if (version != -1) {
                if (version == 0) {
                    if (witnessLength == 20) {
                        btcAddress.addressType = AddressType.P2WPKH;
                    } else if (witnessLength == 32) {
                        btcAddress.addressType = AddressType.P2WSH;
                    }
                } else if (version == 1) {
                    btcAddress.addressType = AddressType.P2TR;
                }
                btcAddress.implementationHash = witPro;
                return btcAddress;
            }
        }
    }

    /**
     * @dev Returns the script hash from a P2SH (pay to script hash) script out.
     * @return hash The recipient script hash, or 0 if verification failed.
     */
    function decodeP2SH(bytes calldata script) internal pure returns (bytes20) {
        if (script.length != P2SH_SCRIPT_LENGTH) {
            return 0;
        }
        // OP_HASH <data 20> OP_EQUAL
        if (script[0] != OP_HASH160 || script[1] != PUSH_20 || script[22] != OP_EQUAL) {
            return 0;
        }
        return bytes20(script[P2SH_ADDRESS_START:P2SH_ADDRESS_END]);
    }

    /**
     * @dev Returns the pubkey hash from a P2PKH (pay to pubkey hash) script out.
     * @return hash The recipient public key hash, or 0 if verification failed.
     */
    function decodeP2PKH(bytes calldata script) internal pure returns (bytes20) {
        if (script.length != P2PKH_SCRIPT_LENGTH) {
            return 0;
        }
        // OP_DUB OP_HASH160 <pubKeyHash 20> OP_EQUALVERIFY OP_CHECKSIG
        if (
            script[0] != OP_DUB || script[1] != OP_HASH160 || script[2] != PUSH_20 || script[23] != OP_EQUALVERIFY
                || script[24] != OP_CHECKSIG
        ) {
            return 0;
        }
        return bytes20(script[P2PKH_ADDRESS_START:P2PKH_ADDRESS_END]);
    }

    /**
     * @dev Returns the witness program segwit tx.
     * @return version The script version, or -1 if verification failed.
     * @return witnessLength The length of the witness program. Should either be 20 or 32.
     * @return witPro The witness program, or nothing if verification failed.
     */
    function decodeWitnessProgram(bytes calldata script)
        internal
        pure
        returns (int8 version, uint8 witnessLength, bytes32 witPro)
    {
        bytes1 versionBytes1 = script[0];
        if (versionBytes1 == OP_0) {
            version = 0;
        } else if ((uint8(OP_1) <= uint8(versionBytes1) && uint8(versionBytes1) <= uint8(OP_16))) {
            unchecked {
                version = int8(uint8(versionBytes1)) - int8(uint8(LESS_THAN_OP_1));
            }
        } else {
            return (version = -1, witnessLength = 0, witPro = bytes32(script[0:0]));
        }
        // Check that the length is given and correct.
        uint8 length_byte = uint8(bytes1(script[1]));
        // Check if the length is between 1 and 75. If it is more than 75, we need to decode the length in a different way. Currently, only length 20 and 32 are used.
        if (1 <= length_byte && length_byte <= 75) {
            if (script.length == length_byte + 2) {
                return (version, witnessLength = length_byte, witPro = bytes32(script[2:]));
            }
        }
        return (version = -1, witnessLength = 0, bytes32(script[0:0]));
    }

    //--- Bitcoin Script Encoding Helpers ---//

    /**
     * @notice Global helper for encoding Bitcoin scripts
     */
    function getBitcoinScript(BitcoinAddress calldata btcAddress) internal pure returns (bytes memory script) {
        // Check if segwit
        if (btcAddress.addressType == AddressType.P2PKH) return scriptP2PKH(bytes20(btcAddress.implementationHash));
        if (btcAddress.addressType == AddressType.P2SH) return scriptP2SH(bytes20(btcAddress.implementationHash));
        if (btcAddress.addressType == AddressType.P2WPKH) {
            return scriptP2WPKH(bytes20(btcAddress.implementationHash));
        }
        if (btcAddress.addressType == AddressType.P2SH) {
            return scriptP2WSH(btcAddress.implementationHash);
        }
        if (btcAddress.addressType == AddressType.P2TR) {
            return scriptP2TR(btcAddress.implementationHash);
        }
    }

    /// @notice Get the associated script out for a P2PKH address
    function scriptP2PKH(bytes20 pHash) internal pure returns (bytes memory) {
        // OP_DUB, OP_HASH160, <pubKeyHash 20>, OP_EQUALVERIFY, OP_CHECKSIG
        return bytes.concat(OP_DUB, OP_HASH160, PUSH_20, pHash, OP_EQUALVERIFY, OP_CHECKSIG);
    }

    /// @notice Get the associated script out for a P2SH address
    function scriptP2SH(bytes20 sHash) internal pure returns (bytes memory) {
        // OP_HASH160, <data 20>, OP_EQUAL
        return bytes.concat(OP_HASH160, PUSH_20, sHash, OP_EQUAL);
    }

    function scriptP2WPKH(bytes20 witnessProgram) internal pure returns (bytes memory) {
        // OP_0, <data 20>
        return bytes.concat(OP_0, PUSH_20, witnessProgram);
    }

    function scriptP2WSH(bytes32 witnessProgram) internal pure returns (bytes memory) {
        return bytes.concat(OP_0, PUSH_32, witnessProgram);
    }

    function scriptP2TR(bytes32 witnessProgram) internal pure returns (bytes memory) {
        return bytes.concat(OP_0, PUSH_32, witnessProgram);
    }
}
