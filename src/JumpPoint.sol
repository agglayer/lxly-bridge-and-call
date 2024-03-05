// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "@zkevm/PolygonZkEVMBridge.sol";

contract JumpPoint {
    constructor(
        address bridge,
        uint32 originNetwork,
        address originAssetAddress,
        address callAddress,
        bytes memory callData
    ) payable {
        // transfer the asset to the target contract
        // NOTE: we need to find the address in the current network
        IERC20 asset = IERC20(
            PolygonZkEVMBridge(bridge).tokenInfoToWrappedToken(
                keccak256(abi.encodePacked(originNetwork, originAssetAddress))
            )
        );
        uint256 balance = asset.balanceOf(address(this));
        asset.approve(callAddress, balance);

        // call the target contract with the callData that was received
        (bool success,) = callAddress.call(callData);
        // TODO: implement fallback - if (!success) transferToFallback();
        require(success);

        assembly {
            return(0, 0)
        }
    }
}
