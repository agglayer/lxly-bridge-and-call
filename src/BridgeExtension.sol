// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@zkevm/interfaces/IBridgeMessageReceiver.sol";
import "@zkevm/interfaces/IPolygonZkEVMBridge.sol";
import "@zkevm/PolygonZkEVMBridge.sol";

import "forge-std/console.sol";

/// @dev Used to bypass stack too deep.
struct ClaimProofData {
    bytes32[32] smtProof;
    uint32 index;
    bytes32 mainnetExitRoot;
    bytes32 rollupExitRoot;
}

contract BridgeExtension is IBridgeMessageReceiver, Ownable {
    using SafeERC20 for IERC20;

    PolygonZkEVMBridge public immutable bridge;

    /// @notice The counterparty network, i.e. network that this instance interacts with.
    uint32 public immutable counterpartyNetwork;

    /// @notice Address of the BridgeExtension in the counterparty network.
    address public counterpartyExtension;

    constructor(
        address owner_,
        address bridge_,
        uint32 cpNetwork
    ) Ownable(owner_) {
        require(bridge_ != address(0), "INVALID_BRIDGE");

        bridge = PolygonZkEVMBridge(bridge_);
        counterpartyNetwork = cpNetwork;
    }

    /// @notice Setter for `counterpartyExtension`.
    function setCounterpartyExtension(address cpExtension) external onlyOwner {
        counterpartyExtension = cpExtension;
    }

    /// @notice Bridge and call from this function.
    function bridgeAndCall(
        uint32 destinationNetwork,
        address destinationAddressAsset,
        address destinationAddressMessage,
        address token,
        uint256 amount,
        bytes calldata metadata,
        bytes calldata permitData,
        bool forceUpdateGlobalExitRoot
    ) external payable {
        // transfer assets from caller to this extension
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // allow the bridge to take the assets
        IERC20(token).approve(address(bridge), amount);
        // bridge the assets
        bridge.bridgeAsset(
            destinationNetwork,
            destinationAddressAsset,
            amount,
            token,
            forceUpdateGlobalExitRoot,
            permitData
        );

        // bridge the message
        // TODO: open question!
        // should we force the message to go to our counterparty extension?
        // or do we allow users to send the message to a contract of their choice?
        bridge.bridgeMessage(
            destinationNetwork,
            destinationAddressMessage,
            forceUpdateGlobalExitRoot,
            metadata
        );
    }

    /// @notice Just a wrapper around `PolygonZkEVMBridge.claimAsset(...)`.
    function claimAsset(
        bytes32[32] calldata smtProof, // _DEPOSIT_CONTRACT_TREE_DEPTH
        uint32 index,
        bytes32 mainnetExitRoot,
        bytes32 rollupExitRoot,
        uint32 originNetwork,
        address originTokenAddress,
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        bytes calldata assetMetadata
    ) external {
        try
            bridge.claimAsset(
                smtProof,
                index,
                mainnetExitRoot,
                rollupExitRoot,
                originNetwork,
                originTokenAddress,
                destinationNetwork,
                destinationAddress,
                amount,
                assetMetadata
            )
        {} catch {
            // TODO: TBD - do we even need to care?
            // at this point, assets are locked in the origin network's bridge
            // what do we do if we're unable to claim them from destination network's bridge?
            // what's the current behavior of the bridge if unable to claimAsset?
        }
    }

    /// @notice More than a wrapper, checks that required assets have been claimed,
    /// before executing claimMessage.
    function claimMessage(
        ClaimProofData calldata claimProofData,
        uint256[] calldata dependsOnIndexes,
        uint32 originNetwork,
        address originAddress,
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        bytes calldata messageMetadata
    ) external {
        // assert that all dependencies have been claimed
        for (uint256 i = 0; i < dependsOnIndexes.length; i++) {
            require(
                bridge.isClaimed(dependsOnIndexes[i]),
                "DEPENDENCY_NOT_CLAIMED"
            );
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
            // TODO: in case of error, transfer assets to fallback address
            // TODO: how to find the assets related to this message? can we get that through the indexes?
            // TODO: where is the fallback address? we could encode it into the message metadata?
            // NOTE: we must first VERIFY leaf and only then decode the fallback address from the messageMetadata to avoid attackers
        }
    }

    /// @notice `IBridgeMessageReceiver`'s callback. This is only executed if `bridgeAndCall`'s
    /// `destinationAddressMessage` is the BridgeExtension (in the destination network).
    function onMessageReceived(
        address originAddress,
        uint32 originNetwork,
        bytes calldata data
    ) external payable {
        require(msg.sender == address(bridge), "NOT_BRIDGE");
        require(originNetwork == counterpartyNetwork, "INVALID_NETWORK");
        require(originAddress == counterpartyExtension, "INVALID_ADDRESS");

        // decode data and do a dynamic call
        // the first 20 bytes are the target contract's address
        address targetContract;
        bytes memory addrData = data[:20]; // data is in calldata, assembly works with memory
        assembly {
            targetContract := mload(add(addrData, 20))
        }

        // make the dynamic call to the contract
        // the remaining bytes have the selector+args
        (bool success, ) = targetContract.call(data[20:]);
        require(success);
    }
}
