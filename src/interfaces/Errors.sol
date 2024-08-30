// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { OrderContext, OrderStatus } from "../interfaces/Structs.sol";

error CannotProveOrder(); // 0x5276f999
error ChallengeDeadlinePassed(); // 0x9b741c77
error CodeSize0(); // 0xfbc1d8e2
error FailedValidation(); // 0xbba6fbc6
error FillDeadlineFarInFuture(); // 0x9dcd54b9
error FillDeadlineInPast(); // 0x8cddc02b
error InitiateDeadlineAfterFill(); // 0xc0bf59b1
error InitiateDeadlinePassed(); // 0x606ef7f5
error InvalidDeadlineOrder(); // 0x2494cf80
error InvalidSettlementAddress(); // 0x78c8b5df
error MinOrderPurchaseDiscountTooLow(uint256 minimum, uint256 configured); // 0xf8e451f1
error OnlyFiller(); // 0x422d60ed
error OrderAlreadyClaimed(OrderStatus orderStatus); // 0x87d33f7e
error OrderNotReadyForOptimisticPayout(uint32 time); // 0xe9deeb4d
error ProofPeriodHasNotPassed(uint32 time); // 0x39bd19f3
error PurchaseTimePassed(); // 0xf8e451f1
error WrongChain(uint32 expected, uint32 actual); // 0x264363e1
error WrongOrderStatus(OrderStatus actual); // 0x858c6fe3
error WrongRemoteOracle(bytes32 addressThis, bytes32 expected); // 0xe57d7773
