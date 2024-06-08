// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { OrderContext, OrderStatus } from "../interfaces/Structs.sol";

error OrderNotClaimed(OrderContext orderContext);
error OrderAlreadyClaimed(OrderContext orderContext);
error OrderAlreadyChallanged(OrderContext orderContext);
error WrongOrderStatus(OrderStatus actual);
error NonceClaimed();
error NotOracle();
error ChallangeDeadlinePassed();
error ProofPeriodHasNotPassed();
error OrderNotReadyForOptimisticPayout();
