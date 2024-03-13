// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {BaseTest} from "./BaseTest.sol";
import {BridgeExtension} from "../../src/BridgeExtension.sol";

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external returns (uint256 amountOut);
}

contract Uniswapper {
    BridgeExtension internal _bridgeExtension;
    ISwapRouter internal _router;
    address internal _alice;
    address internal _l2NativeConverter;

    constructor(address beAddr, address routerAddr, address alice, address l2ncAddr) {
        _router = ISwapRouter(routerAddr);
        _bridgeExtension = BridgeExtension(beAddr);
        _alice = alice;
        _l2NativeConverter = l2ncAddr;
    }

    function approveSwapBridgeBackAndConvert(address tokenIn, address tokenOut, uint256 amount) external {
        // tx funds to this, and perform swap on uniswap router
        IERC20 tIn = IERC20(tokenIn);
        tIn.transferFrom(msg.sender, address(this), amount);
        tIn.approve(address(_router), amount);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams(
            tokenIn,
            tokenOut,
            3000, // 0.3% pool
            address(this),
            block.timestamp + 86400,
            amount,
            0,
            0
        );
        _router.exactInputSingle(params);

        // bridge back and call native converter
        IERC20 tOut = IERC20(tokenOut);
        amount = tOut.balanceOf(address(this));
        tOut.approve(address(_bridgeExtension), amount);

        _bridgeExtension.bridgeAndCall(
            tokenOut,
            amount,
            "",
            1, // network id for L2
            _l2NativeConverter,
            address(0), // fallback
            abi.encodeWithSelector(bytes4(keccak256("convert(address,uint256,bytes)")), _alice, amount, ""),
            true
        );
    }
}

contract ZkEVM2ETHMainnet is BaseTest {
    address internal _targetContract;

    function setUp() public override {
        super.setUp();

        // deploy the target contract in L1
        vm.selectFork(_l1Fork);
        _targetContract = address(
            new Uniswapper(
                address(_l2BridgeExtension),
                vm.envAddress("ADDRESS_L1_UNISWAP_ROUTER"),
                _alice,
                vm.envAddress("ADDRESS_L2_NATIVE_CONVERTER")
            )
        );
    }

    function testBridgeFromL2AndCallL1Uniswap() external {
        vm.selectFork(_l2Fork);
        address l2wmaticAddr = vm.envAddress("ADDRESS_L2_BW_MATIC");
        uint256 amount = _toDecimals(1000, 18);
        deal(l2wmaticAddr, _alice, amount); // fund alice w/ 1K $BWMATIC

        // alice bridges 1000 WMATIC and calls Uniswap
        vm.startPrank(_alice);
        IERC20(l2wmaticAddr).approve(address(_l2BridgeExtension), amount);
        _l2BridgeExtension.bridgeAndCall(
            l2wmaticAddr,
            amount,
            "",
            _l1NetworkId,
            _targetContract,
            address(0), // fallback
            abi.encodeWithSelector(
                bytes4(keccak256("approveSwapBridgeBackAndConvert(address,address,uint256)")),
                vm.envAddress("ADDRESS_L1_MATIC"),
                vm.envAddress("ADDRESS_L1_USDC"),
                amount
            ),
            true
        );
        vm.stopPrank();

        // Claimer claims the asset+message for 1st bridge and call
        _mockClaimL2ToL1();

        // Claimer claims the asset+message for 2nd bridge and call
        _mockClaimL1ToL2();

        // check that the call ran as expected
        vm.selectFork(_l2Fork);
        IERC20 l2usdc = IERC20(vm.envAddress("ADDRESS_L2_USDC"));
        assertGe(l2usdc.balanceOf(_alice), _toDecimals(1000, 6));
    }
}
