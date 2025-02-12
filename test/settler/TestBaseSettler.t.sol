// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";

import { BaseSettler } from "src/settlers/BaseSettler.sol";
import { OrderPurchaseType } from "src/settlers/types/OrderPurchaseType.sol";

interface EIP712 {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract MockSettler is BaseSettler {
    function _domainNameAndVersion() internal pure virtual override returns (string memory name, string memory version) {
        name = "MockSettler";
        version = "-1";
    }

    function maxTimestamp(
        uint32[] calldata timestamps
    ) external pure returns (uint256 timestamp) {
        return _maxTimestamp(timestamps);
    }

    function minTimestamp(
        uint32[] calldata timestamps
    ) external pure returns (uint256 timestamp) {
        return _minTimestamp(timestamps);
    }

    function purchaseGetOrderOwner(bytes32 orderId, bytes32 solver, uint32[] calldata timestamps) external returns (address orderOwner) {
        return _purchaseGetOrderOwner(orderId, solver, timestamps);
    }

    function purchaseOrder(
        bytes32 orderId,
        uint256[2][] calldata inputs,
        bytes32 orderSolvedByIdentifier,
        address purchaser,
        uint256 expiryTimestamp,
        address newDestination,
        bytes calldata call,
        uint48 discount,
        uint32 timeToBuy,
        bytes calldata solverSignature
    ) external {
        _purchaseOrder(orderId, inputs, orderSolvedByIdentifier, purchaser, expiryTimestamp, newDestination, call, discount, timeToBuy, solverSignature);
    }
}

contract TestBaseSettler is Test {
    MockSettler settler;
    bytes32 DOMAIN_SEPARATOR;

    MockERC20 token;
    MockERC20 anotherToken;

    uint256 purchaserPrivateKey;
    address purchaser;
    uint256 solverPrivateKey;
    address solver;

    function getOrderPurchaseSignature(
        uint256 privateKey,
        bytes32 orderId,
        address settlerContract,
        address newDestination,
        bytes calldata call,
        uint64 discount,
        uint32 timeToBuy
    ) external view returns (bytes memory sig) {
        bytes32 msgHash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, OrderPurchaseType.hashOrderPurchase(orderId, settlerContract, newDestination, call, discount, timeToBuy)));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }

    function setUp() public virtual {
        settler = new MockSettler();
        DOMAIN_SEPARATOR = EIP712(address(settler)).DOMAIN_SEPARATOR();

        token = new MockERC20("Mock ERC20", "MOCK", 18);
        anotherToken = new MockERC20("Mock2 ERC20", "MOCK2", 18);

        (purchaser, purchaserPrivateKey) = makeAddrAndKey("purchaser");
        (solver, solverPrivateKey) = makeAddrAndKey("swapper");
    }

    //--- Testing Utility functions ---//

    function test_max_timestamp() external {
        uint32[] memory timestamp_1 = new uint32[](1);
        timestamp_1[0] = 100;

        assertEq(settler.maxTimestamp(timestamp_1), 100);
        vm.snapshotGasLastCall("maxTimestamp1");

        uint32[] memory timestamp_5 = new uint32[](5);
        timestamp_5[0] = 1;
        timestamp_5[1] = 5;
        timestamp_5[2] = 1;
        timestamp_5[3] = 5;
        timestamp_5[4] = 6;

        assertEq(settler.maxTimestamp(timestamp_5), 6);

        timestamp_5[0] = 7;
        assertEq(settler.maxTimestamp(timestamp_5), 7);

        timestamp_5[2] = 3;
        assertEq(settler.maxTimestamp(timestamp_5), 7);
    }

    function test_min_timestamp() external {
        uint32[] memory timestamp_1 = new uint32[](1);
        timestamp_1[0] = 100;

        assertEq(settler.minTimestamp(timestamp_1), 100);
        vm.snapshotGasLastCall("minTimestamp1");

        uint32[] memory timestamp_5 = new uint32[](5);
        timestamp_5[0] = 1;
        timestamp_5[1] = 5;
        timestamp_5[2] = 1;
        timestamp_5[3] = 5;
        timestamp_5[4] = 6;

        assertEq(settler.minTimestamp(timestamp_5), 1);

        timestamp_5[0] = 7;
        assertEq(settler.minTimestamp(timestamp_5), 1);

        timestamp_5[1] = 0;
        assertEq(settler.minTimestamp(timestamp_5), 0);
    }

    //--- Order Purchase ---//

    function test_purchase_order(
        bytes32 orderId
    ) external {
        uint256 amount = 10 ** 18;

        token.mint(purchaser, amount);
        anotherToken.mint(purchaser, amount);

        uint256[2][] memory inputs = new uint256[2][](2);
        inputs[0][0] = uint256(uint160(address(token)));
        inputs[0][1] = amount;
        inputs[1][0] = uint256(uint160(address(anotherToken)));
        inputs[1][1] = amount;

        bytes32 orderSolvedByIdentifier = bytes32(uint256(uint160(solver)));

        uint256 expiryTimestamp = type(uint256).max;
        address newDestination = solver;
        bytes memory call = hex"";
        uint48 discount = 0;
        uint32 timeToBuy = 1000;
        bytes memory solverSignature = this.getOrderPurchaseSignature(solverPrivateKey, orderId, address(settler), newDestination, call, discount, timeToBuy);

        uint32 currentTime = 10000;
        vm.warp(currentTime);

        vm.prank(purchaser);
        token.approve(address(settler), amount);
        vm.prank(purchaser);
        anotherToken.approve(address(settler), amount);

        // Check initial state:
        assertEq(token.balanceOf(solver), 0);
        assertEq(anotherToken.balanceOf(solver), 0);

        (uint32 storageLastOrderTimestamp, address storagePurchaser) = settler.purchasedOrders(orderSolvedByIdentifier, orderId);
        assertEq(storageLastOrderTimestamp, 0);
        assertEq(storagePurchaser, address(0));

        vm.expectCall(address(token), abi.encodeWithSignature("transferFrom(address,address,uint256)", address(purchaser), solver, amount));
        vm.expectCall(address(anotherToken), abi.encodeWithSignature("transferFrom(address,address,uint256)", address(purchaser), solver, amount));

        vm.prank(purchaser);
        settler.purchaseOrder(orderId, inputs, orderSolvedByIdentifier, purchaser, expiryTimestamp, newDestination, call, discount, timeToBuy, solverSignature);
        vm.snapshotGasLastCall("purchaseOrder");

        // Check storage and balances.
        assertEq(token.balanceOf(solver), amount);
        assertEq(anotherToken.balanceOf(solver), amount);

        (storageLastOrderTimestamp, storagePurchaser) = settler.purchasedOrders(orderSolvedByIdentifier, orderId);
        assertEq(storageLastOrderTimestamp, currentTime - timeToBuy);
        assertEq(storagePurchaser, purchaser);

        // Try to purchase the same order again
        vm.expectRevert(abi.encodeWithSignature("AlreadyPurchased()"));
        vm.prank(purchaser);
        settler.purchaseOrder(orderId, inputs, orderSolvedByIdentifier, purchaser, expiryTimestamp, newDestination, call, discount, timeToBuy, solverSignature);
    }

    function test_error_purchase_order_validation(
        bytes32 orderId
    ) external {
        uint256 amount = 10 ** 18;

        token.mint(purchaser, amount);
        anotherToken.mint(purchaser, amount);

        uint256[2][] memory inputs = new uint256[2][](0);

        bytes32 orderSolvedByIdentifier = bytes32(uint256(uint160(solver)));

        uint256 expiryTimestamp = type(uint256).max;
        address newDestination = solver;
        bytes memory call = hex"";
        uint48 discount = 0;
        uint32 timeToBuy = 1000;
        bytes memory solverSignature = this.getOrderPurchaseSignature(solverPrivateKey, orderId, address(settler), newDestination, call, discount, timeToBuy);

        uint32 currentTime = 10000;
        vm.warp(currentTime);

        vm.expectRevert(abi.encodeWithSignature("InvalidPurchaser()"));
        vm.prank(purchaser);
        settler.purchaseOrder(orderId, inputs, orderSolvedByIdentifier, address(0), expiryTimestamp, newDestination, call, discount, timeToBuy, solverSignature);

        vm.expectRevert(abi.encodeWithSignature("Expired()"));
        vm.prank(purchaser);
        settler.purchaseOrder(orderId, inputs, orderSolvedByIdentifier, purchaser, currentTime - 1, newDestination, call, discount, timeToBuy, solverSignature);
    }

    function test_error_purchase_order_validation(bytes32 orderId, bytes calldata solverSignature) external {
        uint256 amount = 10 ** 18;

        token.mint(purchaser, amount);
        anotherToken.mint(purchaser, amount);

        uint256[2][] memory inputs = new uint256[2][](0);

        bytes32 orderSolvedByIdentifier = bytes32(uint256(uint160(solver)));

        uint256 expiryTimestamp = type(uint256).max;
        address newDestination = solver;
        bytes memory call = hex"";
        uint48 discount = 0;
        uint32 timeToBuy = 1000;

        uint32 currentTime = 10000;
        vm.warp(currentTime);

        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        vm.prank(purchaser);
        settler.purchaseOrder(orderId, inputs, orderSolvedByIdentifier, purchaser, expiryTimestamp, newDestination, call, discount, timeToBuy, solverSignature);
    }

    function test_purchase_order_call(bytes32 orderId, bytes calldata call) external {
        vm.assume(call.length > 0);
        uint256 amount = 10 ** 18;

        token.mint(purchaser, amount);
        anotherToken.mint(purchaser, amount);

        uint256[2][] memory inputs = new uint256[2][](2);
        inputs[0][0] = uint256(uint160(address(token)));
        inputs[0][1] = amount;
        inputs[1][0] = uint256(uint160(address(anotherToken)));
        inputs[1][1] = amount;

        bytes32 orderSolvedByIdentifier = bytes32(uint256(uint160(solver)));

        uint256 expiryTimestamp = type(uint256).max;
        address newDestination = address(this);
        uint48 discount = 0;
        uint32 timeToBuy = 1000;
        bytes memory solverSignature = this.getOrderPurchaseSignature(solverPrivateKey, orderId, address(settler), newDestination, call, discount, timeToBuy);

        uint32 currentTime = 10000;
        vm.warp(currentTime);

        vm.prank(purchaser);
        token.approve(address(settler), amount);
        vm.prank(purchaser);
        anotherToken.approve(address(settler), amount);

        vm.prank(purchaser);
        settler.purchaseOrder(orderId, inputs, orderSolvedByIdentifier, purchaser, expiryTimestamp, newDestination, call, discount, timeToBuy, solverSignature);

        assertEq(abi.encodePacked(_inputs), abi.encodePacked(inputs));
        assertEq(_executionData, call);
    }

    function test_error_dependent_on_purchase_order_call(bytes32 orderId, bytes calldata call) external {
        vm.assume(call.length > 0);
        uint256 amount = 10 ** 18;

        token.mint(purchaser, amount);

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0][0] = uint256(uint160(address(token)));
        inputs[0][1] = amount;

        bytes32 orderSolvedByIdentifier = bytes32(uint256(uint160(solver)));

        uint256 expiryTimestamp = type(uint256).max;
        address newDestination = address(this);
        uint48 discount = 0;
        uint32 timeToBuy = 1000;
        bytes memory solverSignature = this.getOrderPurchaseSignature(solverPrivateKey, orderId, address(settler), newDestination, call, discount, timeToBuy);

        uint32 currentTime = 10000;
        vm.warp(currentTime);

        vm.prank(purchaser);
        token.approve(address(settler), amount);

        failExternalCall = true;
        vm.expectRevert(abi.encodeWithSignature("ExternalFail()"));

        vm.prank(purchaser);
        settler.purchaseOrder(orderId, inputs, orderSolvedByIdentifier, purchaser, expiryTimestamp, newDestination, call, discount, timeToBuy, solverSignature);
    }

    error ExternalFail();

    bool failExternalCall;
    uint256[2][] _inputs;
    bytes _executionData;

    function inputsFilled(uint256[2][] calldata inputs, bytes calldata executionData) external {
        if (failExternalCall) revert ExternalFail();

        _inputs = inputs;
        _executionData = executionData;
    }

    //--- Purchase Resolution ---//

    function test_purchase_order_then_resolve(
        bytes32 orderId
    ) external {
        uint256 amount = 10 ** 18;

        token.mint(purchaser, amount);

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0][0] = uint256(uint160(address(token)));
        inputs[0][1] = amount;

        bytes32 orderSolvedByIdentifier = bytes32(uint256(uint160(solver)));

        uint256 expiryTimestamp = type(uint256).max;
        address newDestination = solver;
        bytes memory call = hex"";
        uint48 discount = 0;
        uint32 timeToBuy = 1000;
        bytes memory solverSignature = this.getOrderPurchaseSignature(solverPrivateKey, orderId, address(settler), newDestination, call, discount, timeToBuy);

        uint32 currentTime = 10000;
        vm.warp(currentTime);

        vm.prank(purchaser);
        token.approve(address(settler), amount);
        vm.prank(purchaser);
        anotherToken.approve(address(settler), amount);

        vm.prank(purchaser);
        settler.purchaseOrder(orderId, inputs, orderSolvedByIdentifier, purchaser, expiryTimestamp, newDestination, call, discount, timeToBuy, solverSignature);

        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = currentTime;

        address collectedPurchaser = settler.purchaseGetOrderOwner(orderId, orderSolvedByIdentifier, timestamps);

        assertEq(collectedPurchaser, purchaser);
    }

    function test_purchase_order_then_resolve_early_first_fill_late_last(
        bytes32 orderId
    ) external {
        uint256 amount = 10 ** 18;

        token.mint(purchaser, amount);

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0][0] = uint256(uint160(address(token)));
        inputs[0][1] = amount;

        bytes32 orderSolvedByIdentifier = bytes32(uint256(uint160(solver)));

        uint256 expiryTimestamp = type(uint256).max;
        address newDestination = solver;
        bytes memory call = hex"";
        uint48 discount = 0;
        uint32 timeToBuy = 1000;
        bytes memory solverSignature = this.getOrderPurchaseSignature(solverPrivateKey, orderId, address(settler), newDestination, call, discount, timeToBuy);

        uint32 currentTime = 10000;
        vm.warp(currentTime);

        vm.prank(purchaser);
        token.approve(address(settler), amount);
        vm.prank(purchaser);
        anotherToken.approve(address(settler), amount);

        vm.prank(purchaser);
        settler.purchaseOrder(orderId, inputs, orderSolvedByIdentifier, purchaser, expiryTimestamp, newDestination, call, discount, timeToBuy, solverSignature);

        uint32[] memory timestamps = new uint32[](2);
        timestamps[0] = currentTime;
        timestamps[1] = 0;

        address collectedPurchaser = settler.purchaseGetOrderOwner(orderId, orderSolvedByIdentifier, timestamps);

        assertEq(collectedPurchaser, purchaser);
    }

    function test_purchase_order_then_resolve_too_late_purchase(
        bytes32 orderId
    ) external {
        uint256 amount = 10 ** 18;

        token.mint(purchaser, amount);

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0][0] = uint256(uint160(address(token)));
        inputs[0][1] = amount;

        bytes32 orderSolvedByIdentifier = bytes32(uint256(uint160(solver)));

        uint256 expiryTimestamp = type(uint256).max;
        address newDestination = solver;
        bytes memory call = hex"";
        uint48 discount = 0;
        uint32 timeToBuy = 1000;
        bytes memory solverSignature = this.getOrderPurchaseSignature(solverPrivateKey, orderId, address(settler), newDestination, call, discount, timeToBuy);

        uint32 currentTime = 10000;
        vm.warp(currentTime);

        vm.prank(purchaser);
        token.approve(address(settler), amount);
        vm.prank(purchaser);
        anotherToken.approve(address(settler), amount);

        vm.prank(purchaser);
        settler.purchaseOrder(orderId, inputs, orderSolvedByIdentifier, purchaser, expiryTimestamp, newDestination, call, discount, timeToBuy, solverSignature);

        uint32[] memory timestamps = new uint32[](2);
        timestamps[0] = currentTime - timeToBuy - 1;
        timestamps[1] = 0;

        address collectedPurchaser = settler.purchaseGetOrderOwner(orderId, orderSolvedByIdentifier, timestamps);

        assertEq(collectedPurchaser, solver);
    }

    function test_purchase_order_no_purchase(bytes32 orderId, bytes32 orderSolvedByIdentifier) external {
        uint32[] memory timestamps = new uint32[](2);

        address collectedPurchaser = settler.purchaseGetOrderOwner(orderId, orderSolvedByIdentifier, timestamps);
        assertEq(collectedPurchaser, address(uint160(uint256(orderSolvedByIdentifier))));
    }
}
