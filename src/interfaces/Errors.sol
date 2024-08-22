// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { OrderContext, OrderStatus } from "../interfaces/Structs.sol";

error BackupOnlyCallableByFiller(address filler, address msgSender); // 0x892bc944
error CannotProveOrder(); // 0x5276f999
error ChallengeDeadlinePassed(); // 0x9b741c77
error CodeSize0(); // 0xfbc1d8e2
error FailedValidation(); // 0xbba6fbc6
error FillTimeFarInFuture(); // 0x9dcd54b9
error FillTimeInPast(); // 0x8cddc02b
error InitiateDeadlineAfterFill(); // 0xc0bf59b1
error InitiateDeadlinePassed(); // 0x606ef7f5
error InvalidDeadlineOrder(); // 0x2494cf80
error OnlyFiller(); // 0x422d60ed
error OrderAlreadyClaimed(OrderStatus orderStatus); // 0x87d33f7e
error OrderNotReadyForOptimisticPayout(uint32 timeRemaining); // 0xe9deeb4d
error ProofPeriodHasNotPassed(uint32 timeRemaining); // 0x39bd19f3
error PurchaseTimePassed(); // 0xf8e451f1
error WrongChain(uint32 expected, uint32 actual); // 0x264363e1
error WrongOrderStatus(OrderStatus actual); // 0x858c6fe3
