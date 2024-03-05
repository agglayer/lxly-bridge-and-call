// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

interface IBridgeAndCall {
    function bridgeAndCall(
        address token,
        uint256 amount,
        bytes calldata permitData,
        uint32 destinationNetwork,
        address callAddress,
        bytes calldata callData,
        bool forceUpdateGlobalExitRoot
    ) external payable;
}
