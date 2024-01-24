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
    address public destinationAddress;

    constructor(
        uint32 destinationNetwork_,
        address originNetworkBridgeExtension_,
        address destinationBridgeExtension_,
        address destinationAddress_
    ) {
        destinationNetwork = destinationNetwork_; // L2
        originNetworkBridgeExtension = BridgeExtension(
            originNetworkBridgeExtension_
        );
        destinationBridgeExtension = destinationBridgeExtension_;
        destinationAddress = destinationAddress_;
    }

    function buyL2TokenWithL1Token(
        address sourceToken,
        address targetToken,
        uint256 amountToSpend,
        bytes calldata permitData,
        address receiver
    ) external {
        IERC20(sourceToken).transferFrom(
            msg.sender,
            address(originNetworkBridgeExtension),
            amountToSpend
        );

        // calldata format
        // first 20 bytes are the target contract's address
        // remaining bytes are encodedWithSelector: the function selector + arguments

        // this specific example has a nested dynamic call
        // 1st call goes to the receiver contract
        // 2nd call goes to the quickswap router
        bytes memory callData = abi.encodePacked(
            destinationAddress, // the receiver contract in L2
            abi.encodeWithSelector(
                bytes4(keccak256("approveAndQuickSwap(address,bytes)")),
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
            )
        );

        originNetworkBridgeExtension.bridgeAndCall(
            destinationNetwork,
            destinationAddress, // l2 receiver contract gets the asset
            destinationBridgeExtension, // l2 bridge extension gets the message
            sourceToken,
            amountToSpend,
            callData,
            permitData,
            true
        );
    }
}
