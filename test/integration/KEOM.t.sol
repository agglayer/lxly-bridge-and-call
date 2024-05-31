// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {KEOMDepositor} from "./demo/KEOMDepositor.sol";
import {BaseTest} from "./BaseTest.sol";

contract KEOM is BaseTest {
    address internal _l1Matic;
    address internal _l2BWMatic;
    address internal _l2kMatic;
    address internal _keomDepositor;

    function setUp() public override {
        super.setUp();

        _l1Matic = vm.envAddress("ADDRESS_L1_MATIC");
        _l2BWMatic = vm.envAddress("ADDRESS_L2_BW_MATIC");
        _l2kMatic = vm.envAddress("ADDRESS_L2_KMATIC");

        // deploy test contracts
        vm.startPrank(_deployer);
        vm.selectFork(_l2Fork);
        _keomDepositor = address(new KEOMDepositor());
        vm.stopPrank();

        // fund alice with 1M L1 MATIC
        vm.selectFork(_l1Fork);
        deal(_l1Matic, _alice, _toDecimals(1000000, 18));
    }

    // TEST

    function testBridgeAndDepositMATIC() public {
        vm.selectFork(_l1Fork);
        vm.startPrank(_alice);
        uint256 amount = _toDecimals(1000, 18);
        IERC20(_l1Matic).approve(address(_l1BridgeExtension), amount);

        bytes memory callData = abi.encodeWithSelector(
            bytes4(keccak256("mintAndTransfer(address,address,uint256,address)")),
            _l2BWMatic, // l2 token (MATIC)
            _l2kMatic, // cToken
            amount, // amount
            _alice // receiver
        );
        _l1BridgeExtension.bridgeAndCall(
            _l1Matic,
            amount,
            _l2NetworkId,
            _keomDepositor,
            address(0), // fallback address
            callData,
            true
        );
        vm.stopPrank();

        vm.selectFork(_l2Fork);
        assertEq(IERC20(_l2kMatic).balanceOf(_alice), 0);

        // Claimer claims the asset+message
        _mockClaimL1ToL2();

        vm.selectFork(_l2Fork);
        assertGt(IERC20(_l2kMatic).balanceOf(_alice), 0); // 4954050148480
    }
}
