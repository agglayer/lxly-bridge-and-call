// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Test, console} from "forge-std/Test.sol";
import {BridgeExtension} from "../src/BridgeExtension.sol";
import {MockBridge} from "../src/mocks/MockBridge.sol";
import {DemoL1SenderDynamicCall} from "../src/demo/DemoL1Sender.sol";
import {DemoL2Receiver} from "../src/demo/DemoL2Receiver.sol";

contract BridgeAndCallTest is Test {
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
        _deployer = vm.addr(0);
        _alice = vm.addr(1);
        _bob = vm.addr(2);
        _claimer = vm.addr(9);

        _usdc = vm.envAddress("ADDRESS_L1_USDC");
        _matic = vm.envAddress("ADDRESS_L2_MATIC");

        // deploy and init contracts
        _deployMockBridge();
        _deployContracts();

        // fund alice with 1M L1 USDC
        vm.selectFork(_l1Fork);
        deal(_usdc, _alice, 10 ** 6 * 10 ** 6);
        // fund claimer with 1M L2 ETH
        vm.selectFork(_l2Fork);
        deal(_claimer, 10 ** 6 * 10 ** 18);
    }

    function _deployMockBridge() internal virtual {
        vm.selectFork(_l1Fork);
        MockBridge mb1 = new MockBridge();
        bytes memory mb1Code = address(mb1).code;
        vm.etch(_bridge, mb1Code);

        vm.selectFork(_l2Fork);
        MockBridge mb2 = new MockBridge();
        bytes memory mb2Code = address(mb2).code;
        vm.etch(_bridge, mb2Code);
    }

    function _deployContracts() internal virtual {
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
        ) = b.lastBridgeMessage();
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
        ) = b.lastBridgeMessage();
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

        // mine a few blocks
        // TODO

        // claimer claims the asset+message
        vm.startPrank(_claimer);
        _claimAsset(_l1Fork, _l2Fork);
        _claimMessage(_l1Fork, _l2Fork);
        vm.stopPrank();
    }
}
