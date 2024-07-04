// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { OrderContext, OrderStatus } from "../interfaces/Structs.sol";

error OrderNotClaimed(OrderContext orderContext);
error OrderAlreadyClaimed(OrderContext orderContext);
error OrderAlreadyChallenged(OrderContext orderContext);
error WrongOrderStatus(OrderStatus actual);
error NonceClaimed();
error NotOracle();
error ChallengedeadlinePassed();
error ProofPeriodHasNotPassed();
error OrderNotReadyForOptimisticPayout(uint40 timeRemaining);
error CannotProveOrder();
error WrongChain();
error FillTimeInPast();
error FillTimeFarInFuture();
error InvalidDeadline();
error ChellengeAfterProofDeadline();
error StartTimeAfterEndTime();
