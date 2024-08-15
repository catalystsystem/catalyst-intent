// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { OrderContext, OrderStatus } from "../interfaces/Structs.sol";

error OrderNotClaimed(OrderStatus orderStatus);
error OrderAlreadyClaimed(OrderStatus orderStatus);
error OrderAlreadyChallenged(OrderStatus orderStatus);
error WrongOrderStatus(OrderStatus actual);
error NonceClaimed();
error NotOracle();
error ChallengeDeadlinePassed();
error ProofPeriodHasNotPassed(uint32 timeRemaining);
error OrderNotReadyForOptimisticPayout(uint32 timeRemaining);
error OnlyFiller();
error CannotProveOrder();
error WrongChain();
error FailedValidation();
error FillTimeInPast();
error FillTimeFarInFuture();
error InitiateDeadlineAfterFill();
error InitiateDeadlinePassed();
error InvalidDeadlineOrder();
error LengthsNotEqual();
error PurchaseTimePassed();
error CodeSize0();
