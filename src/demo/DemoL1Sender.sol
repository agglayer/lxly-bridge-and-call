// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BridgeExtension.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

struct ExactInputSingleParams {
    address tokenIn;
    address tokenOut;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
    uint160 limitSqrtPrice;
}

contract DemoL1SenderDynamicCall {
    BridgeExtension public originNetworkBridgeExtension;
    address public destinationBridgeExtension;
    uint32 public destinationNetwork;

    constructor(
        address originNetworkBridgeExtension_,
        address destinationBridgeExtension_,
        uint32 destinationNetwork_
    ) {
        originNetworkBridgeExtension = BridgeExtension(
            originNetworkBridgeExtension_
        );
        destinationBridgeExtension = destinationBridgeExtension_;
        destinationNetwork = destinationNetwork_; // L2
    }

    function buyL2TokenWithL1Token(
        address sourceToken,
        address targetToken,
        uint256 amountToSpend,
        bytes calldata permitData,
        address receiver
    ) external {
        // dynamic function call into QuickSwap
        IERC20(sourceToken).transferFrom(
            msg.sender,
            address(originNetworkBridgeExtension),
            amountToSpend
        );

        // calldata format
        // first 20 bytes are the target contract's address
        // remaining bytes are encoded with selector - the function selector + arguments
        bytes memory callData = abi.encodePacked(
            0xF6Ad3CcF71Abb3E12beCf6b3D2a74C963859ADCd, // QuickSwap SwapRouter
            abi.encodeWithSelector( // function selector
                bytes4(
                    keccak256(
                        "exactInputSingle((address,address,address,uint256,uint256,uint256,uint160))"
                    )
                ),
                ExactInputSingleParams(
                    0xA8CE8aee21bC2A48a5EF670afCc9274C7bbbC035, // bridge wrapped usdc
                    targetToken,
                    receiver,
                    block.timestamp + 86400,
                    amountToSpend,
                    0,
                    0
                )
            )
        );

        originNetworkBridgeExtension.bridgeAndCall(
            destinationNetwork,
            destinationBridgeExtension,
            sourceToken,
            amountToSpend,
            callData,
            permitData,
            true
        );
    }
}
