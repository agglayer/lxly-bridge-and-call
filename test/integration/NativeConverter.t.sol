// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {BaseTest} from "./BaseTest.sol";

contract NativeConverter is BaseTest {
    address internal _l1Usdc;
    address internal _l2Usdc;
    address internal _l2BridgeWrappedUsdc;
    address internal _nativeConverter;

    function setUp() public override {
        super.setUp();

        _l1Usdc = vm.envAddress("ADDRESS_L1_USDC");
        _l2Usdc = vm.envAddress("ADDRESS_L2_USDC");
        _l2BridgeWrappedUsdc = vm.envAddress("ADDRESS_L2_BWUSDC");
        _nativeConverter = vm.envAddress("ADDRESS_L2_NATIVE_CONVERTER");

        // fund alice with 1M L1 USDC
        _dealL1Usdc(_alice, _toDecimals(1000000, 6));
    }

    // HELPERS

    /// USDC changed its contract and broke Foundry's `deal`
    function _dealL1Usdc(address target, uint256 amount) internal {
        vm.startPrank(0xD6153F5af5679a75cC85D8974463545181f48772); // USDC WHALE
        vm.selectFork(_l1Fork);
        IERC20(_l1Usdc).transfer(target, amount);
        vm.stopPrank();
    }

    // TEST

    function testBridgeAndConvertUSDC() public {
        vm.selectFork(_l1Fork);
        vm.startPrank(_alice);

        uint256 amount = _toDecimals(1000, 6);
        assertGe(IERC20(_l1Usdc).balanceOf(_alice), amount);

        // bridge L1 USDC to L2 and call NativeConvert.convert
        IERC20(_l1Usdc).approve(address(_l1BridgeExtension), amount);
        bytes memory callData =
            abi.encodeWithSelector(bytes4(keccak256("convert(address,uint256,bytes)")), _alice, amount, "");
        _l1BridgeExtension.bridgeAndCall(
            _l1Usdc,
            amount,
            "", // no permit data
            _l2NetworkId,
            _nativeConverter,
            address(0), // fallback address
            callData,
            true
        );
        vm.stopPrank();

        // check that Alice doesn't have any L2 USDC yet
        vm.selectFork(_l2Fork);
        assertEq(IERC20(_l2Usdc).balanceOf(_alice), 0);

        // Claimer claims the asset+message
        _mockClaimL1ToL2();

        // check that the convert happened and Alice got the USDC
        vm.selectFork(_l2Fork);
        assertEq(IERC20(_l2Usdc).balanceOf(_alice), amount);
    }
}
