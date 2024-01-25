// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../BridgeExtension.sol";

struct ExactInputSingleParams {
    address tokenIn;
    address tokenOut;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
    uint160 limitSqrtPrice;
}

/// @notice Demo contract that triggers `bridgeAndCall` through `buyL2TokenWithL1Token`.
contract DemoL1SenderDynamicCall {
    using SafeERC20 for IERC20;

    /// @notice The Bridge Extension in L1 (origin network).
    BridgeExtension public l1BridgeExtension;

    /// @notice The Bridge Extension address in L2 (destination network).
    address public l2BridgeExtension;

    /// @notice The destination network id.
    uint32 public l2NetworkId;

    /// @notice The address of the contract that will receive the assets, and ultimately get called.
    address public l2Receiver;

    constructor(
        uint32 l2NetworkId_,
        address l1BridgeExtension_,
        address l2BridgeExtension_,
        address l2Receiver_
    ) {
        l2NetworkId = l2NetworkId_;
        l1BridgeExtension = BridgeExtension(l1BridgeExtension_);
        l2BridgeExtension = l2BridgeExtension_;
        l2Receiver = l2Receiver_;
    }

    function buyL2TokenWithL1Token(
        address l1Token,
        address l2Token,
        uint256 amountToSpend,
        bytes calldata permitData,
        address receiver
    ) external {
        // transfer the assets from the caller to this contract (the extension will take it from here)
        IERC20(l1Token).safeTransferFrom(
            msg.sender,
            address(this),
            amountToSpend
        );
        // allow the extension to take the assets
        IERC20(l1Token).approve(address(l1BridgeExtension), amountToSpend);

        // callData is just encodedWithSelector: the function selector + arguments

        // this specific demo has a nested dynamic call, just to show that it's possible
        // 1st call goes to the receiver contract
        // 2nd call goes to the quickswap router
        bytes memory callData = abi.encodeWithSelector(
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
                    l2Token,
                    receiver,
                    block.timestamp + 86400,
                    amountToSpend,
                    0,
                    0
                )
            )
        );

        l1BridgeExtension.bridgeAndCall(
            l1Token,
            amountToSpend,
            permitData,
            l2NetworkId,
            l2Receiver, // the receiver contract in L2
            callData,
            true
        );
    }
}
