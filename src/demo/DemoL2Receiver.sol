// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract DemoL2Receiver {
    function approveAndQuickSwap(
        address quickswapRouter,
        bytes memory data
    ) external payable {
        // approve bridge wrapped usdc to be used by quickswap router
        IERC20(0xA8CE8aee21bC2A48a5EF670afCc9274C7bbbC035).approve(
            quickswapRouter,
            1000 * 10 ** 6
        );

        // do the swap
        (bool success, ) = quickswapRouter.call(data);
        require(success);

        // above dynamic call is equivalent to:
        // ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
        //     .ExactInputSingleParams(
        //         0xA8CE8aee21bC2A48a5EF670afCc9274C7bbbC035,
        //         0xa2036f0538221a77A3937F1379699f44945018d0,
        //         0x2B5AD5c4795c026514f8317c7a215E218DcCD6cF,
        //         block.timestamp + 86400,
        //         1000 * 10 ** 6,
        //         0,
        //         0
        //     );
        // ISwapRouter(targetContract).exactInputSingle(params);
    }
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 limitSqrtPrice;
    }

    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut);
}
