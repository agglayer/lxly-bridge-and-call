// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

interface IBridgeAndCall {
    function bridgeAndCall(
        address token,
        uint256 amount,
        uint32 destinationNetwork,
        address callAddress,
        address fallbackAddress,
        bytes calldata callData,
        bool forceUpdateGlobalExitRoot
    ) external payable;
}
