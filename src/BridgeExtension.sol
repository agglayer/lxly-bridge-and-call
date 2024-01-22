// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@zkevm/interfaces/IPolygonZkEVMBridge.sol";

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
        bytes calldata permitData,
        bytes calldata metadata,
        bool forceUpdateGlobalExitRoot
    ) external payable {
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
        // TODO: validations etc
        // origin network == source network
        // origin address == source bridge extension

        // TODO: decode data and do a dynamic call
        address targetContract = abi.decode(data[:20], (address));

        (bool success, ) = targetContract.call(data[19:]);
        require(success);
    }
}
