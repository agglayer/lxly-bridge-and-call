// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {BridgeExtension} from "../src/BridgeExtension.sol";
import {MockBridge} from "../src/mocks/MockBridge.sol";
import {DemoL1SenderDynamicCall} from "../src/demo/DemoL1Sender.sol";
import {DemoL2Receiver} from "../src/demo/DemoL2Receiver.sol";

contract BridgeAndCall is Test {
    uint256 internal _l1Fork;
    uint256 internal _l2Fork;
    uint32 internal _l1NetworkId;
    uint32 internal _l2NetworkId;

    address internal _bridge;
    address internal _usdc;
    address internal _matic;

    address internal _deployer;
    address internal _alice;
    address internal _bob;
    address internal _claimer;

    BridgeExtension internal _l1BridgeExtension;
    BridgeExtension internal _l2BridgeExtension;
    DemoL1SenderDynamicCall internal _l1SenderContract;

    function setUp() public {
        // create the forks
        _l1Fork = vm.createFork(vm.envString("L1_RPC_URL"));
        _l2Fork = vm.createFork(vm.envString("L2_RPC_URL"));
        _l1NetworkId = uint32(vm.envUint("L1_NETWORK_ID"));
        _l2NetworkId = uint32(vm.envUint("L2_NETWORK_ID"));

        // retrieve the addresses
        _bridge = vm.envAddress("ADDRESS_LXLY_BRIDGE");
        _usdc = vm.envAddress("ADDRESS_L1_USDC");
        _matic = vm.envAddress("ADDRESS_L2_MATIC");

        _alice = vm.addr(1);
        _bob = vm.addr(2);
        _claimer = vm.addr(8);
        _deployer = vm.addr(9);

        // deploy and init contracts
        _deployMockBridge();
        _deployContracts();

        // fund alice with 1M L1 USDC
        _dealUSDC(_alice, 1000000);
    }

    function _dealUSDC(address target, uint256 amountInUsd) internal {
        vm.startPrank(0xD6153F5af5679a75cC85D8974463545181f48772); // USDC WHALE
        vm.selectFork(_l1Fork);
        IERC20(_usdc).transfer(target, amountInUsd * 10 ** 6);
        vm.stopPrank();
    }

    function _deployMockBridge() internal {
        vm.startPrank(_deployer);
        vm.selectFork(_l1Fork);
        MockBridge mb1 = new MockBridge();
        bytes memory mb1Code = address(mb1).code;
        vm.etch(_bridge, mb1Code);

        vm.selectFork(_l2Fork);
        MockBridge mb2 = new MockBridge();
        bytes memory mb2Code = address(mb2).code;
        vm.etch(_bridge, mb2Code);
        vm.stopPrank();
    }

    function _deployContracts() internal {
        vm.startPrank(_deployer);

        // deploy L1 Bridge Extension
        vm.selectFork(_l1Fork);
        _l1BridgeExtension = new BridgeExtension(_bridge);

        // deploy L2 Bridge Extension
        vm.selectFork(_l2Fork);
        _l2BridgeExtension = new BridgeExtension(_bridge);

        // deploy DemoL1Sender
        vm.selectFork(_l1Fork);
        _l1SenderContract = new DemoL1SenderDynamicCall(
            address(_l1BridgeExtension),
            address(_l2BridgeExtension),
            _l2NetworkId
        );

        vm.stopPrank();
    }

    function _claimMessage(uint256 from, uint256 to) internal {
        MockBridge b = MockBridge(_bridge);

        vm.selectFork(from);
        (
            uint32 originNetwork,
            address originAddress,
            uint32 destinationNetwork,
            address destinationAddress,
            uint256 amount,
            bytes memory metadata
        ) = b.lastBridgeMessageMsg();
        // proof can be empty because our MockBridge bypasses the merkle tree verification
        // i.e. _verifyLeaf is always successful
        bytes32[32] memory proof;

        vm.selectFork(to);
        b.claimMessage(
            proof,
            uint32(b.depositCount()),
            "",
            "",
            originNetwork,
            originAddress,
            destinationNetwork,
            destinationAddress,
            amount,
            metadata
        );
    }

    function _claimAsset(uint256 from, uint256 to) internal {
        MockBridge b = MockBridge(_bridge);

        vm.selectFork(from);
        (
            uint32 originNetwork,
            address originTokenAddress,
            uint32 destinationNetwork,
            address destinationAddress,
            uint256 amount,
            bytes memory metadata
        ) = b.lastBridgeAssetMsg();
        // proof and index can be empty because our MockBridge bypasses the merkle tree verification
        // i.e. _verifyLeaf is always successful
        bytes32[32] memory proof;
        uint32 index;

        vm.selectFork(to);
        b.claimAsset(
            proof,
            index,
            "",
            "",
            originNetwork,
            originTokenAddress,
            destinationNetwork,
            destinationAddress,
            amount,
            metadata
        );
    }

    function test_buyL2TokenWithL1Token() public {
        // alice issues a buy order in L1
        vm.selectFork(_l1Fork);
        vm.startPrank(_alice);
        uint256 amount = 1000 * 10 ** 6;
        IERC20(_usdc).approve(address(_l1SenderContract), amount);
        // this bridges the assets and a message to L2 BridgeExtension
        _l1SenderContract.buyL2TokenWithL1Token(
            _usdc,
            _matic,
            amount,
            "",
            _bob
        );
        vm.stopPrank();

        // check that bob doesn't have any matic yet
        vm.selectFork(_l2Fork);
        assertEq(IERC20(_matic).balanceOf(_bob), 0);

        // claimer claims the asset+message
        vm.startPrank(_claimer);
        _claimAsset(_l1Fork, _l2Fork);
        _claimMessage(_l1Fork, _l2Fork);
        vm.stopPrank();

        // check that the swap happened and bob got the matic
        vm.selectFork(_l2Fork);
        assertGt(IERC20(_matic).balanceOf(_bob), 0);
    }
}
