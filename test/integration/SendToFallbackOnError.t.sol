// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {BaseTest} from "./BaseTest.sol";

contract FailingContract {
    function doSomething() external pure {
        assert(false);
    }
}

contract SendToFallBackOnError is BaseTest {
    address internal _l1Matic;
    address internal _l2BWMatic;
    address internal failContract;

    function setUp() public override {
        super.setUp();

        _l1Matic = vm.envAddress("ADDRESS_L1_MATIC");
        _l2BWMatic = vm.envAddress("ADDRESS_L2_BW_MATIC");

        // fund alice with 1M L1 MATIC
        vm.selectFork(_l1Fork);
        deal(_l1Matic, _alice, _toDecimals(1000000, 18));

        vm.selectFork(_l2Fork);
        failContract = address(new FailingContract());
    }

    function testCallFailsButSendsERC20AssetsToFallback() public {
        vm.selectFork(_l1Fork);
        vm.startPrank(_alice);
        uint256 amount = _toDecimals(1000, 18);

        IERC20(_l1Matic).approve(address(_l1BridgeExtension), amount);
        _l1BridgeExtension.bridgeAndCall(
            _l1Matic,
            amount,
            "",
            _l2NetworkId,
            failContract,
            _chad, // fallback address
            abi.encodeWithSelector(bytes4(keccak256("doSomething()"))),
            true
        );
        vm.stopPrank();

        // Claimer claims the asset+message
        _mockClaim();

        // the bridgeAndCall to FailingContract reverts, so asset is routed to the fallback address (bob)
        vm.selectFork(_l2Fork);
        assertEq(IERC20(_l2BWMatic).balanceOf(_chad), amount);
    }

    function testCallFailsButSendsNativeETHToFallback() public {
        vm.selectFork(_l1Fork);
        deal(_alice, 10 ** 25); // fund alice

        vm.startPrank(_alice);
        uint256 amount = _toDecimals(1000, 18);

        _l1BridgeExtension.bridgeAndCall{value: amount}(
            address(0),
            amount,
            "",
            _l2NetworkId,
            failContract,
            _chad, // fallback address
            abi.encodeWithSelector(bytes4(keccak256("doSomething()"))),
            true
        );
        vm.stopPrank();

        // Claimer claims the asset+message
        _mockClaim();

        // the bridgeAndCall to FailingContract reverts, so asset is routed to the fallback address (bob)
        vm.selectFork(_l2Fork);
        assertEq(_chad.balance, amount);
    }
}
