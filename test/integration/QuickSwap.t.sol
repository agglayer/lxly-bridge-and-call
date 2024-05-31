// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {QuickSwapL1Sender} from "./demo/QuickSwapL1Sender.sol";
import {QuickSwapL2Receiver} from "./demo/QuickSwapL2Receiver.sol";
import {BaseTest} from "./BaseTest.sol";

contract QuickSwap is BaseTest {
    address internal _l1Usdc;
    address internal _l2Matic;

    QuickSwapL1Sender internal _l1SenderContract;
    QuickSwapL2Receiver internal _l2ReceiverContract;

    function setUp() public override {
        super.setUp();

        _l1Usdc = vm.envAddress("ADDRESS_L1_USDC");
        _l2Matic = vm.envAddress("ADDRESS_L2_BW_MATIC");

        // deploy test contracts
        vm.startPrank(_deployer);
        vm.selectFork(_l2Fork);
        _l2ReceiverContract = new QuickSwapL2Receiver();

        vm.selectFork(_l1Fork);
        _l1SenderContract = new QuickSwapL1Sender(
            _l2NetworkId, address(_l1BridgeExtension), address(_l2BridgeExtension), address(_l2ReceiverContract)
        );
        vm.stopPrank();

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

    function testBuyL2TokenWithL1Token() public {
        // Alice issues a buy order in L1 of 1000 USDC, for L2 MATIC to be sent to Bob
        vm.selectFork(_l1Fork);
        vm.startPrank(_alice);
        uint256 amount = _toDecimals(1000, 6);
        IERC20(_l1Usdc).approve(address(_l1SenderContract), amount);
        _l1SenderContract.buyL2TokenWithL1Token(_l1Usdc, _l2Matic, amount, _bob);
        vm.stopPrank();

        // check that Bob doesn't have any L2 MATIC yet
        vm.selectFork(_l2Fork);
        assertEq(IERC20(_l2Matic).balanceOf(_bob), 0);

        // Claimer claims the asset+message
        _mockClaimL1ToL2();

        // check that the swap happened and Bob got the MATIC
        vm.selectFork(_l2Fork);
        assertGt(IERC20(_l2Matic).balanceOf(_bob), _toDecimals(880, 18)); // ATTN: swap rate of 1 USDC == 0.88 MATIC
    }
}
