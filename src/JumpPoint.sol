// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@zkevm/PolygonZkEVMBridge.sol";

contract JumpPoint {
    using SafeERC20 for IERC20;

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
        asset.safeTransfer(callAddress, balance);

        // call the target contract with the callData that was received
        (bool success, ) = callAddress.call(callData);
        // TODO: implement fallback - if (!success) transferToFallback();
        require(success);
    }
}
