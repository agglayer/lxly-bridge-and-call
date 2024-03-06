// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "@zkevm/PolygonZkEVMBridge.sol";

contract JumpPoint {
    constructor(
        address bridge,
        uint32 originNetwork,
        address originAssetAddress,
        address callAddress,
        address fallbackAddress,
        bytes memory callData
    ) payable {
        // TODO: support native asset

        // transfer the asset to the target contract
        IERC20 asset = IERC20(
            // NOTE: this weird logic is how we find the address in the current network
            PolygonZkEVMBridge(bridge).tokenInfoToWrappedToken(
                keccak256(abi.encodePacked(originNetwork, originAssetAddress))
            )
        );
        uint256 balance = asset.balanceOf(address(this));
        asset.approve(callAddress, balance);

        // call the target contract with the callData that was received
        (bool success,) = callAddress.call(callData);
        if (!success) {
            asset.transfer(fallbackAddress, balance);
        }

        assembly {
            return(0, 0)
        }
    }
}
