// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@zkevm/interfaces/IPolygonZkEVMBridge.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import "forge-std/console.sol";

// to bypass stack too deep
struct ClaimProofData {
    bytes32[32] smtProof;
    uint32 index;
    bytes32 mainnetExitRoot;
    bytes32 rollupExitRoot;
}

/// @title
/// @notice
contract BridgeExtension {
    IPolygonZkEVMBridge public bridge;

    constructor(address bridge_) {
        require(bridge_ != address(0), "INVALID_BRIDGE");

        bridge = IPolygonZkEVMBridge(bridge_);
    }

    function bridgeAndCall(
        uint32 destinationNetwork,
        address destinationAddress,
        address token,
        uint256 amount,
        bytes calldata metadata,
        bytes calldata permitData,
        bool forceUpdateGlobalExitRoot
    ) external payable {
        IERC20(token).approve(address(bridge), amount);
        bridge.bridgeAsset(
            destinationNetwork,
            destinationAddress,
            amount,
            token,
            forceUpdateGlobalExitRoot,
            permitData
        );

        bridge.bridgeMessage(
            destinationNetwork,
            destinationAddress,
            forceUpdateGlobalExitRoot,
            metadata
        );
    }

    // TODO: break this down into 2 functions because frontrunning attacks on claimAsset can break this
    // i.e. someone independently calls claimAsset - this function won't run anymore
    function claimBridgeAndCall(
        ClaimProofData calldata claimProofData,
        uint32 originNetwork,
        address originTokenAddress,
        address originAddress,
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        bytes calldata assetMetadata,
        bytes calldata messageMetadata
    ) external {
        try
            bridge.claimAsset(
                claimProofData.smtProof,
                claimProofData.index,
                claimProofData.mainnetExitRoot,
                claimProofData.rollupExitRoot,
                originNetwork,
                originTokenAddress,
                destinationNetwork,
                destinationAddress,
                amount,
                assetMetadata
            )
        {} catch {
            // TODO: return asset
        }

        try
            bridge.claimMessage(
                claimProofData.smtProof,
                claimProofData.index,
                claimProofData.mainnetExitRoot,
                claimProofData.rollupExitRoot,
                originNetwork,
                originAddress,
                destinationNetwork,
                destinationAddress,
                amount,
                messageMetadata
            )
        {} catch {
            // TODO: return asset
        }
    }

    function onMessageReceived(
        address,
        uint32,
        bytes calldata data
    ) external payable {
        console.log("HELLO!");
        // origin network == source network
        // origin address == source bridge extension

        // TODO: decode data and do a dynamic call
        // the first 20 bytes are the target contract's address
        address targetContract;
        bytes memory addrData = data[:20]; // data is in calldata, assembly works with memory
        assembly {
            targetContract := mload(add(addrData, 20))
        }

        // TODO: TEMP - remove
        IERC20(0xA8CE8aee21bC2A48a5EF670afCc9274C7bbbC035).approve(
            targetContract,
            1000 * 10 ** 6
        );

        // make the dynamic call to the contract
        // the remaining bytes have the selector+args
        (bool success, ) = targetContract.call(data[20:]);
        require(success);
    }
}
