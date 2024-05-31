// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@zkevm/interfaces/IBridgeMessageReceiver.sol";
import "@zkevm/v2/PolygonZkEVMBridgeV2.sol";

import {IBridgeAndCall} from "./IBridgeAndCall.sol";
import {JumpPoint} from "./JumpPoint.sol";

error AmountDoesNotMatchMsgValue();
error InvalidAddress();
error InvalidDepositIndex();
error OriginMustBeBridgeExtension();
error SenderMustBeBridge();
error UnclaimedAsset();

contract BridgeExtension is IBridgeAndCall, IBridgeMessageReceiver, Initializable {
    using SafeERC20 for IERC20;

    PolygonZkEVMBridgeV2 public bridge;

    constructor() {}

    function initialize(address bridge_) external initializer {
        if (bridge_ == address(0)) revert InvalidAddress();

        bridge = PolygonZkEVMBridgeV2(bridge_);
    }

    /// @notice Bridge and call from this function.
    function bridgeAndCall(
        address token,
        uint256 amount,
        uint32 destinationNetwork,
        address callAddress,
        address fallbackAddress,
        bytes calldata callData,
        bool forceUpdateGlobalExitRoot
    ) external payable {
        // calculate the depends on index based on the number of bridgeAssets we're doing
        uint256 dependsOnIndex = bridge.depositCount() + 1; // only doing 1 bridge asset

        if (token != address(0) && token == address(bridge.WETHToken())) {
            // user is bridging ERC20 (WETH)
            uint256 balanceBefore = IERC20(token).balanceOf(address(this)); // WETH will only be taxable if it's modified by the chain operator

            // transfer assets from caller to this extension
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

            uint256 balanceAfter = IERC20(token).balanceOf(address(this));
            amount = balanceAfter - balanceBefore;

            // transfer the erc20 - using a helper to get rid of stack too deep
            _bridgeNativeWETHAssetHelper(
                token, amount, destinationNetwork, callAddress, fallbackAddress, callData, dependsOnIndex
            );
        } else if (token == address(0)) {
            // user is bridging the gas token
            if (msg.value != amount) {
                revert AmountDoesNotMatchMsgValue();
            }

            // transfer native gas token (e.g. eth) - using a helper to get rid of stack too deep
            _bridgeNativeAssetHelper(amount, destinationNetwork, callAddress, fallbackAddress, callData, dependsOnIndex);
        } else {
            // user is bridging ERC20 - beware of tax tokens
            uint256 balanceBefore = IERC20(token).balanceOf(address(this));

            // transfer assets from caller to this extension
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

            uint256 balanceAfter = IERC20(token).balanceOf(address(this));
            amount = balanceAfter - balanceBefore;

            // transfer the erc20 - using a helper to get rid of stack too deep
            _bridgeERC20AssetHelper(
                token, amount, destinationNetwork, callAddress, fallbackAddress, callData, dependsOnIndex
            );
        }

        // assert that the index is correct - avoid any potential reentrancy caused by bridgeAsset
        if (dependsOnIndex != bridge.depositCount()) revert InvalidDepositIndex();

        bytes memory encodedMsg;
        if (token != address(0) && token == address(bridge.WETHToken())) {
            encodedMsg =
                abi.encode(dependsOnIndex, callAddress, fallbackAddress, bridge.networkID(), address(0), callData);
        } else if (token == address(0)) {
            // bridge the message (which gets encoded with extra data) to the extension on the destination network
            encodedMsg = abi.encode(
                dependsOnIndex,
                callAddress,
                fallbackAddress,
                bridge.gasTokenNetwork(),
                bridge.gasTokenAddress(),
                callData
            );
        } else {
            // we need to encode the correct token network/address
            (uint32 assetOriginalNetwork, address assetOriginalAddr) = bridge.wrappedTokenToTokenInfo(token);
            if (assetOriginalAddr == address(0)) {
                // only do this when the token is not from this network
                assetOriginalNetwork = bridge.networkID();
                assetOriginalAddr = token;
            }

            // bridge the message (which gets encoded with extra data) to the extension on the destination network
            encodedMsg = abi.encode(
                dependsOnIndex, callAddress, fallbackAddress, assetOriginalNetwork, assetOriginalAddr, callData
            );
        }

        bridge.bridgeMessage(destinationNetwork, address(this), forceUpdateGlobalExitRoot, encodedMsg);
    }

    function _bridgeNativeWETHAssetHelper(
        address token,
        uint256 amount,
        uint32 destinationNetwork,
        address callAddress,
        address fallbackAddress,
        bytes calldata callData,
        uint256 dependsOnIndex
    ) internal {
        // pre-compute the address of the JumpPoint contract so we can bridge the assets
        address jumpPointAddr = _computeJumpPointAddress(
            dependsOnIndex, bridge.networkID(), address(0), callAddress, fallbackAddress, callData
        );

        // allow the bridge to take the assets
        IERC20(token).approve(address(bridge), amount);

        // bridge the ERC20 assets
        bridge.bridgeAsset(destinationNetwork, jumpPointAddr, amount, token, false, "");
    }

    function _bridgeNativeAssetHelper(
        uint256 amount,
        uint32 destinationNetwork,
        address callAddress,
        address fallbackAddress,
        bytes calldata callData,
        uint256 dependsOnIndex
    ) internal {
        // pre-compute the address of the JumpPoint contract so we can bridge the assets
        address jumpPointAddr = _computeJumpPointAddress(
            dependsOnIndex, bridge.gasTokenNetwork(), bridge.gasTokenAddress(), callAddress, fallbackAddress, callData
        );

        // bridge the native assets
        bridge.bridgeAsset{value: amount}(destinationNetwork, jumpPointAddr, amount, address(0), false, "");
    }

    function _bridgeERC20AssetHelper(
        address token,
        uint256 amount,
        uint32 destinationNetwork,
        address callAddress,
        address fallbackAddress,
        bytes calldata callData,
        uint256 dependsOnIndex
    ) internal {
        address jumpPointAddr;

        {
            // we need to encode the correct token network/address
            (uint32 assetOriginalNetwork, address assetOriginalAddr) = bridge.wrappedTokenToTokenInfo(token);
            if (assetOriginalAddr == address(0)) {
                // only do this when the token is not from this network
                assetOriginalNetwork = bridge.networkID();
                assetOriginalAddr = token;
            }

            // pre-compute the address of the JumpPoint contract so we can bridge the assets
            jumpPointAddr = _computeJumpPointAddress(
                dependsOnIndex, assetOriginalNetwork, assetOriginalAddr, callAddress, fallbackAddress, callData
            );
        }

        // allow the bridge to take the assets
        IERC20(token).approve(address(bridge), amount);

        // bridge the ERC20 assets
        bridge.bridgeAsset(destinationNetwork, jumpPointAddr, amount, token, false, "");
    }

    /// @dev Helper function to pre-compute the jumppoint address (the contract pseudo-deployed using create2).
    /// NOTE: inlining into `_bridgeAssetHelper` triggers a `Stack too deep`.
    function _computeJumpPointAddress(
        uint256 dependsOnIndex,
        uint32 assetNetwork,
        address assetAddress,
        address callAddress,
        address fallbackAddress,
        bytes memory callData
    ) internal view returns (address) {
        // JumpPoint is deployed using CREATE2, so we are able to pre-compute the address
        // of the JumpPoint instance in advance, in order to bridge the assets to it
        bytes memory bytecode = abi.encodePacked(
            type(JumpPoint).creationCode,
            abi.encode(address(bridge), assetNetwork, assetAddress, callAddress, fallbackAddress, callData)
        );

        // this just follows the CREATE2 address computation algo
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this), // deployer = counterparty bridge extension AKA "this"
                bytes32(dependsOnIndex), // salt = the depends on index
                keccak256(bytecode)
            )
        );
        // cast last 20 bytes of hash to address
        return address(uint160(uint256(hash)));
    }

    /// @notice `IBridgeMessageReceiver`'s callback. This is only executed if `bridgeAndCall`'s
    /// `destinationAddressMessage` is the BridgeExtension (in the destination network).
    function onMessageReceived(address originAddress, uint32 originNetwork, bytes calldata data) external payable {
        if (msg.sender != address(bridge)) revert SenderMustBeBridge();
        if (originAddress != address(this)) revert OriginMustBeBridgeExtension(); // BridgeExtension must have the same address in all networks

        // decode the index for bridgeAsset, and check that it has been claimed
        (
            uint256 dependsOnIndex,
            address callAddress,
            address fallbackAddress,
            uint32 assetOriginalNetwork,
            address assetOriginalAddress,
            bytes memory callData
        ) = abi.decode(data, (uint256, address, address, uint32, address, bytes));
        if (!bridge.isClaimed(uint32(dependsOnIndex), originNetwork)) revert UnclaimedAsset();

        // the remaining bytes have the selector+args
        new JumpPoint{salt: bytes32(dependsOnIndex)}(
            address(bridge), assetOriginalNetwork, assetOriginalAddress, callAddress, fallbackAddress, callData
        );
    }
}
