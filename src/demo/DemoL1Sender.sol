// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BridgeExtension.sol";

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
        originNetworkBridgeExtension.bridgeAndCall(
            destinationNetwork,
            destinationBridgeExtension,
            sourceToken,
            amountToSpend,
            abi.encode(
                0xF6Ad3CcF71Abb3E12beCf6b3D2a74C963859ADCd, // QuickSwap SwapRouter
                // function selector
                bytes4(
                    keccak256(
                        "exactInputSingle(ISwapRouter.ExactInputSingleParams)"
                    )
                ),
                // ExactInputSingleParams
                abi.encode(
                    sourceToken,
                    targetToken,
                    receiver,
                    block.timestamp + 86400,
                    amountToSpend,
                    0,
                    0
                )
            ),
            permitData,
            true
        );
    }
}

contract DemoL1SenderMessageReceiver {
    BridgeExtension public bridgeExtension;
    uint32 public destinationNetwork;
    address public destinationAddress;

    constructor(address bridgeExtension_, uint32 destinationNetwork_) {
        bridgeExtension = BridgeExtension(bridgeExtension_);
        destinationNetwork = destinationNetwork_; // L2
    }

    function setDestinationAddress(address destinationAddress_) external {
        // TODO: onlyOwner etc
        destinationAddress = destinationAddress_;
    }

    // function buyL2TokenWithL1Token(
    //     address sourceToken,
    //     address targetToken,
    //     uint256 amountToSpend,
    //     bytes calldata permitData
    // ) external {
    //     // DemoL2Receiver gets called
    //     bridgeExtension.bridgeAndCall(
    //         destinationNetwork,
    //         sourceToken,
    //         amountToSpend,
    //         destinationAddress,
    //         abi.encode(targetToken),
    //         permitData,
    //         true
    //     );
    // }
}
