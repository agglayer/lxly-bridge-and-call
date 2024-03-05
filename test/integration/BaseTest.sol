// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {BridgeExtension} from "../../src/BridgeExtension.sol";
import {BridgeExtensionProxy} from "../../src/BridgeExtensionProxy.sol";
import {MockBridgeV2} from "./mocks/MockBridgeV2.sol";

abstract contract BaseTest is Test {
    uint256 internal _l1Fork;
    uint256 internal _l2Fork;
    uint32 internal _l1NetworkId;
    uint32 internal _l2NetworkId;

    address internal _bridge;

    address internal _deployer;
    address internal _alice;
    address internal _bob;
    address internal _claimer;

    BridgeExtension internal _l1BridgeExtension;
    BridgeExtension internal _l2BridgeExtension;

    function setUp() public virtual {
        // create the forks
        _l1Fork = vm.createFork(vm.envString("L1_RPC_URL"));
        _l2Fork = vm.createFork(vm.envString("L2_RPC_URL"));
        _l1NetworkId = uint32(vm.envUint("L1_NETWORK_ID"));
        _l2NetworkId = uint32(vm.envUint("L2_NETWORK_ID"));

        // retrieve the addresses
        _bridge = vm.envAddress("ADDRESS_LXLY_BRIDGE");

        _alice = vm.addr(1);
        _bob = vm.addr(2);
        _claimer = vm.addr(8);
        _deployer = vm.addr(9);

        // deploy and init contracts
        _deployMockBridge();
        _deployContracts();
    }

    // HELPERS

    function _deployMockBridge() private {
        vm.startPrank(_deployer);
        vm.selectFork(_l1Fork);
        MockBridgeV2 mb1 = new MockBridgeV2();
        bytes memory mb1Code = address(mb1).code;
        vm.etch(_bridge, mb1Code);

        vm.selectFork(_l2Fork);
        MockBridgeV2 mb2 = new MockBridgeV2();
        bytes memory mb2Code = address(mb2).code;
        vm.etch(_bridge, mb2Code);
        vm.stopPrank();
    }

    function _deployContracts() private {
        vm.startPrank(_deployer);
        uint256 salt = 1234567890;

        // deploy L1 Bridge Extension
        vm.selectFork(_l1Fork);
        BridgeExtensionProxy bep1 = new BridgeExtensionProxy{salt: bytes32(salt)}(
            _deployer, address(new BridgeExtension{salt: bytes32(salt)}()), _deployer, _bridge
        );
        _l1BridgeExtension = BridgeExtension(address(bep1));

        // deploy L2 Bridge Extension
        vm.selectFork(_l2Fork);
        BridgeExtensionProxy bep2 = new BridgeExtensionProxy{salt: bytes32(salt)}(
            _deployer, address(new BridgeExtension{salt: bytes32(salt)}()), _deployer, _bridge
        );
        _l2BridgeExtension = BridgeExtension(address(bep2));

        vm.stopPrank();
    }

    function _mockClaimAsset(uint256 from, uint256 to) internal {
        MockBridgeV2 b = MockBridgeV2(_bridge);

        vm.selectFork(from);
        (
            uint32 originNetwork,
            address originTokenAddress,
            uint32 destinationNetwork,
            address destinationAddress,
            uint256 amount,
            bytes memory metadata
        ) = b.lastBridgeAssetMsg();

        // proof and index can be empty because our MockBridgeV2 bypasses the merkle tree verification
        // i.e. _verifyLeaf is always successful
        bytes32[32] memory smtProofLocalExitRoot;
        bytes32[32] memory smtProofRollupExitRoot;
        uint32 index;

        vm.selectFork(to);
        b.claimAsset(
            smtProofLocalExitRoot,
            smtProofRollupExitRoot,
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

    function _mockClaimMessage(uint256 from, uint256 to) internal {
        MockBridgeV2 b = MockBridgeV2(_bridge);

        vm.selectFork(from);
        (
            uint32 originNetwork,
            address originAddress,
            uint32 destinationNetwork,
            address destinationAddress,
            uint256 amount,
            bytes memory metadata
        ) = b.lastBridgeMessageMsg();

        // proof can be empty because our MockBridgeV2 bypasses the merkle tree verification
        // i.e. _verifyLeaf is always successful
        bytes32[32] memory smtProofLocalExitRoot;
        bytes32[32] memory smtProofRollupExitRoot;

        vm.selectFork(to);
        b.claimMessage(
            smtProofLocalExitRoot,
            smtProofRollupExitRoot,
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

    function _mockClaim() internal {
        vm.startPrank(_claimer);
        _mockClaimAsset(_l1Fork, _l2Fork);
        _mockClaimMessage(_l1Fork, _l2Fork);
        vm.stopPrank();
    }

    function _toDecimals(uint256 value, uint256 decimals) internal pure returns (uint256) {
        return value * 10 ** decimals;
    }
}
