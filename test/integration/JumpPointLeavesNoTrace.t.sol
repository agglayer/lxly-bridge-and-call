// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {JumpPoint} from "../../src/JumpPoint.sol";

import {BaseTest} from "./BaseTest.sol";
import {MockBridgeV2} from "./mocks/MockBridgeV2.sol";

contract TargetContract {
    function doNothing() external pure {
        // meh
    }
}

contract JumpPointLeavesNoTrace is BaseTest {
    address internal _l1Matic;
    address internal _l2BWMatic;
    address internal _targetContract;

    function setUp() public override {
        super.setUp();

        _l1Matic = vm.envAddress("ADDRESS_L1_MATIC");
        _l2BWMatic = vm.envAddress("ADDRESS_L2_BW_MATIC");

        // fund alice with 1M L1 MATIC
        vm.selectFork(_l1Fork);
        deal(_l1Matic, _alice, _toDecimals(1000000, 18));

        vm.selectFork(_l2Fork);
        _targetContract = address(new TargetContract());
    }

    function testJumpPointRunsAndLeavesNoCodeBehind() public {
        vm.selectFork(_l1Fork);

        // keep track of this for calculating the jumppoint address
        uint256 depositCount = MockBridgeV2(_bridge).depositCount();
        bytes memory callData = abi.encodeWithSelector(bytes4(keccak256("doNothing()")));

        // alice bridges 1000 MATIC and calls TargetContract.doNothing()
        vm.startPrank(_alice);
        uint256 amount = _toDecimals(1000, 18);
        IERC20(_l1Matic).approve(address(_l1BridgeExtension), amount);
        _l1BridgeExtension.bridgeAndCall(_l1Matic, amount, "", _l2NetworkId, _targetContract, _bob, callData, true);
        vm.stopPrank();

        // Claimer claims the asset+message
        _mockClaim();

        // check that no code remains at the jumppoint address
        vm.selectFork(_l2Fork);
        address jpAddr = _computeJumpPointAddress(uint256(depositCount + 1), _l1Matic, _targetContract, _bob, callData);
        uint32 size;
        assembly {
            size := extcodesize(jpAddr)
        }
        assertEq(size, 0);

        // but the bridge MATIC is still there, since no one moved it
        assertEq(IERC20(_l2BWMatic).balanceOf(jpAddr), amount);
    }

    /// @dev adapted copy of BridgeExtension's `_computeJumpPointAddress`.
    function _computeJumpPointAddress(
        uint256 dependsOnIndex,
        address originAssetAddress,
        address callAddress,
        address fallbackAddress,
        bytes memory callData
    ) internal view returns (address) {
        bytes memory bytecode = abi.encodePacked(
            type(JumpPoint).creationCode,
            abi.encode(
                address(_bridge),
                0, // current network = L1
                originAssetAddress,
                callAddress,
                fallbackAddress,
                callData
            )
        );

        // precompute address that will be the receiver of the assets
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(_l1BridgeExtension), // deployer = counterparty bridge extension
                bytes32(dependsOnIndex), // salt = the depends on index
                keccak256(bytecode)
            )
        );
        // cast last 20 bytes of hash to address
        return address(uint160(uint256(hash)));
    }
}
