// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

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
contract BridgeAndCall {
    IPolygonZkEVMBridge public bridge;

    constructor(address bridge_) {
        require(bridge_ != address(0), "INVALID_BRIDGE");

        bridge = IPolygonZkEVMBridge(bridge_);
    }

    function bridgeAndCall(
        uint32 destinationNetwork,
        address token,
        uint256 amount,
        address destinationAddress,
        bytes calldata metadata,
        bytes calldata permitData,
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
}
