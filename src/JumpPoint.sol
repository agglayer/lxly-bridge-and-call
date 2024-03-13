// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "@zkevm/v2/PolygonZkEVMBridgeV2.sol";

contract JumpPoint {
    constructor(
        address bridge,
        uint32 assetOriginalNetwork,
        address assetOriginalAddress,
        address callAddress,
        address fallbackAddress,
        bytes memory callData
    ) payable {
        PolygonZkEVMBridgeV2 zkBridge = PolygonZkEVMBridgeV2(bridge);

        // determine what got transferred to this jumppoint
        IERC20 asset;
        // origin asset is empty, then it's either gas token or weth
        if (assetOriginalAddress == address(0)) {
            // asset is WETHToken if exists, or native gas token
            asset = zkBridge.WETHToken();
        }
        // origin asset is not empty, then it's either gas token or erc20
        else {
            if (
                assetOriginalAddress == zkBridge.gasTokenAddress() && assetOriginalNetwork == zkBridge.gasTokenNetwork()
            ) {
                // it was the native gas token (not eth)
                // asset will be null (use msg.value)
            } else {
                // it was an erc20

                // The token is an ERC20 from this network
                if (assetOriginalNetwork == zkBridge.networkID()) {
                    asset = IERC20(assetOriginalAddress);
                }
                // The token is an ERC20 NOT from this network
                else {
                    asset = IERC20(
                        // NOTE: this weird logic is how we find the corresponding asset address in the current network
                        zkBridge.tokenInfoToWrappedToken(
                            keccak256(abi.encodePacked(assetOriginalNetwork, assetOriginalAddress))
                        )
                    );
                }
            }
        }

        // if it's a native gas token (eth or other) => call using msg.value
        // otherwise it's an erc20 => approve spending and call
        if (address(asset) == address(0)) {
            uint256 balance = address(this).balance; // because we don't receive the amount

            // call the target contract with the callData that was received, passing the native token
            (bool success,) = callAddress.call{value: balance}(callData);

            // if call was unsuccessful, then transfer the native token to the fallback address
            if (!success) fallbackAddress.call{value: balance}("");
        } else {
            uint256 balance = asset.balanceOf(address(this)); // because we don't receive the amount

            // call the target contract with the callData that was received, allowing the erc20 to be taken
            asset.approve(callAddress, balance);
            (bool success,) = callAddress.call(callData);

            // if call was unsuccessful, then transfer the asset to the fallback address
            if (!success) asset.transfer(fallbackAddress, balance);
        }

        // perform a cleanup
        assembly {
            return(0, 0)
        }
    }
}
