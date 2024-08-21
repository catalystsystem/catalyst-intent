// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { OrderContext, OrderStatus } from "../interfaces/Structs.sol";

error BackupOnlyCallableByFiller(address filler, address msgSender);
error CannotProveOrder();
error ChallengeDeadlinePassed();
error CodeSize0();
error FailedValidation();
error FillTimeFarInFuture();
error FillTimeInPast();
error InitiateDeadlineAfterFill();
error InitiateDeadlinePassed();
error InvalidDeadlineOrder();
error OnlyFiller();
error OrderAlreadyClaimed(OrderStatus orderStatus);
error OrderNotReadyForOptimisticPayout(uint32 timeRemaining);
error ProofPeriodHasNotPassed(uint32 timeRemaining);
error PurchaseTimePassed();
error WrongChain(uint32 expected, uint32 actual);
error WrongOrderStatus(OrderStatus actual);
