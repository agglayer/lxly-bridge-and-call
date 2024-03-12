// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {BaseTest} from "./BaseTest.sol";
import {MockBridgeV2} from "./mocks/MockBridgeV2.sol";

interface IPolygonBridge {
    function WETHToken() external returns (address);
}

contract EthProcessor {
    address internal bridge;

    constructor(address bridge_) {
        bridge = bridge_;
    }

    function splitGasToken(address alice, address bob) external payable {
        uint256 splitAmt = msg.value / 2;

        (bool sentAlice, bytes memory dataAlice) = alice.call{value: splitAmt}("");
        (bool sentBob, bytes memory dataBob) = bob.call{value: splitAmt}("");

        assert(sentAlice == sentBob == true);
    }

    function _splitERC20(address erc20, address first, address second, uint256 amount) internal {
        IERC20 erc20 = IERC20(erc20);
        erc20.transferFrom(msg.sender, address(this), amount);

        uint256 splitAmt = amount / 2;
        erc20.transfer(first, splitAmt);
        erc20.transfer(second, splitAmt);
    }

    function splitMatic(address alice, address bob, uint256 amount) external payable {
        // zkmainnet wmatic
        _splitERC20(0xa2036f0538221a77A3937F1379699f44945018d0, alice, bob, amount);
    }

    function splitBitcorn(address alice, address bob, uint256 amount) external payable {
        // zkmainnet wbtc
        _splitERC20(0xEA034fb02eB1808C2cc3adbC15f447B93CbE08e1, alice, bob, amount);
    }

    function splitNativeWETH(address alice, address bob, uint256 amount) external payable {
        IPolygonBridge bridge = IPolygonBridge(bridge);
        _splitERC20(bridge.WETHToken(), alice, bob, amount);
    }
}

contract BridgeWithDifferentAssetTypes is BaseTest {
    address internal _l1Matic;
    address internal _l2BWMatic;
    address internal _targetContract;

    function setUp() public override {
        super.setUp();

        // deploy the target contract in L2
        vm.selectFork(_l2Fork);
        _targetContract = address(new EthProcessor(_bridge));
    }

    // A1. bridgeAsset(eth) where Lx_gas==eth && Ly_gas==eth
    // result: receives gas token (eth)
    function testBridgeEthGasTokenAndCall() external {
        vm.selectFork(_l1Fork);
        uint256 amount = _toDecimals(1000, 18);
        deal(_alice, amount); // fund alice

        // alice bridges 1000 ETH and calls EthProcessor.splitGasToken()
        vm.startPrank(_alice);
        _l1BridgeExtension.bridgeAndCall{value: amount}(
            address(0),
            amount,
            "",
            _l2NetworkId,
            _targetContract,
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("splitGasToken(address,address)")), _alice, _bob),
            true
        );
        vm.stopPrank();

        // Claimer claims the asset+message
        _mockClaim();

        // check that the call ran as expected
        vm.selectFork(_l2Fork);
        assertEq(_alice.balance, amount / 2);
        assertEq(_bob.balance, amount / 2);
    }

    // A2. bridgeAsset(erc20) where Lx_gas==eth && Ly_gas==eth
    // result: receives erc20
    function testBridgeERC20MaticAndCall() external {
        vm.selectFork(_l1Fork);

        // setup the erc20 in Lx
        uint256 amount = _toDecimals(1000, 18);
        address l1MaticAddr = vm.envAddress("ADDRESS_L1_MATIC");
        deal(l1MaticAddr, _alice, amount); // fund alice

        // alice bridges 1000 MATIC and calls EthProcessor.splitMatic()
        vm.startPrank(_alice);
        IERC20(l1MaticAddr).approve(address(_l1BridgeExtension), amount);
        _l1BridgeExtension.bridgeAndCall(
            l1MaticAddr,
            amount,
            "",
            _l2NetworkId,
            _targetContract,
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("splitMatic(address,address,uint256)")), _alice, _bob, amount),
            true
        );
        vm.stopPrank();

        // Claimer claims the asset+message
        _mockClaim();

        // check that the call ran as expected
        vm.selectFork(_l2Fork);
        IERC20 l2wmatic = IERC20(vm.envAddress("ADDRESS_L2_BW_MATIC"));
        assertEq(l2wmatic.balanceOf(_alice), amount / 2);
        assertEq(l2wmatic.balanceOf(_bob), amount / 2);
    }

    // A3. bridgeAsset(eth) where Lx_gas==eth && Ly_gas!=eth
    // result: receives Ly.WETH
    function testBridgeEthAndCallIntoNonETHChain() external {
        // change the native gas token of Ly
        vm.selectFork(_l2Fork);
        MockBridgeV2 b = MockBridgeV2(_bridge);
        b.changeGasTokenToUSDCe();

        vm.selectFork(_l1Fork);
        uint256 amount = _toDecimals(1000, 18);
        deal(_alice, amount); // fund alice

        // alice bridges 1000 ETH and calls EthProcessor.splitNativeWETH()
        vm.startPrank(_alice);
        _l1BridgeExtension.bridgeAndCall{value: amount}(
            address(0),
            amount,
            "",
            _l2NetworkId,
            _targetContract,
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("splitNativeWETH(address,address,uint256)")), _alice, _bob, amount),
            true
        );
        vm.stopPrank();

        // Claimer claims the asset+message
        _mockClaim();

        // check that the call ran as expected
        vm.selectFork(_l2Fork);
        IERC20 weth = IERC20(address(b.WETHToken()));
        assertEq(weth.balanceOf(_alice), amount / 2);
        assertEq(weth.balanceOf(_bob), amount / 2);
    }

    // A4. bridgeAsset(erc20) where Lx_gas==eth && Ly_gas!=eth && Ly_gas!=erc20
    // result: receives erc20
    function testBridgeERC20AndCallIntoNonETHChain() external {
        // change the native gas token of Ly
        vm.selectFork(_l2Fork);
        MockBridgeV2 b = MockBridgeV2(_bridge);
        b.changeGasTokenToUSDCe();

        // setup the erc20 in Lx
        vm.selectFork(_l1Fork);
        uint256 amount = _toDecimals(1000, 18);
        address l1MaticAddr = vm.envAddress("ADDRESS_L1_MATIC");
        deal(l1MaticAddr, _alice, amount); // fund alice

        // alice bridges 1000 MATIC and calls EthProcessor.splitMatic()
        vm.startPrank(_alice);
        IERC20(l1MaticAddr).approve(address(_l1BridgeExtension), amount);
        _l1BridgeExtension.bridgeAndCall(
            l1MaticAddr,
            amount,
            "",
            _l2NetworkId,
            _targetContract,
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("splitMatic(address,address,uint256)")), _alice, _bob, amount),
            true
        );
        vm.stopPrank();

        // Claimer claims the asset+message
        _mockClaim();

        // check that the call ran as expected
        vm.selectFork(_l2Fork);
        IERC20 l2wmatic = IERC20(vm.envAddress("ADDRESS_L2_BW_MATIC"));
        assertEq(l2wmatic.balanceOf(_alice), amount / 2);
        assertEq(l2wmatic.balanceOf(_bob), amount / 2);
    }

    // A5. bridgeAsset(erc20) where Lx_gas==eth && Ly_gas==erc20
    // result: receives gas token (equivalent to erc20)
    function testBridgeERC20AndCallIntoERC20Chain() external {
        // change the native gas token of Ly
        vm.selectFork(_l2Fork);
        MockBridgeV2 b = MockBridgeV2(_bridge);
        b.changeGasTokenToL1Matic();

        // setup the erc20 in Lx
        vm.selectFork(_l1Fork);
        uint256 amount = _toDecimals(1000, 18);
        address l1MaticAddr = vm.envAddress("ADDRESS_L1_MATIC");
        deal(l1MaticAddr, _alice, amount); // fund alice

        // alice bridges 1000 MATIC and calls EthProcessor.splitGasToken()
        vm.startPrank(_alice);
        IERC20(l1MaticAddr).approve(address(_l1BridgeExtension), amount);
        _l1BridgeExtension.bridgeAndCall(
            l1MaticAddr,
            amount,
            "",
            _l2NetworkId,
            _targetContract,
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("splitGasToken(address,address)")), _alice, _bob),
            true
        );
        vm.stopPrank();

        // Claimer claims the asset+message
        _mockClaim();

        // check that the call ran as expected
        vm.selectFork(_l2Fork);
        assertEq(_alice.balance, amount / 2);
        assertEq(_bob.balance, amount / 2);
    }

    // B1. bridgeAsset(gas_token) where Lx_gas!=eth && Ly_gas==Lx_gas
    // result: receives gas token
    function testBridgeGasTokenAndCallIntoGasTokenChain() external {
        // change the native gas token of Lx to MATIC
        vm.selectFork(_l1Fork);
        MockBridgeV2 b1 = MockBridgeV2(_bridge);
        b1.changeGasTokenToL1Matic();

        // change the native gas token of Ly to MATIC
        vm.selectFork(_l2Fork);
        MockBridgeV2 b2 = MockBridgeV2(_bridge);
        b2.changeGasTokenToL1Matic();

        vm.selectFork(_l1Fork);
        uint256 amount = _toDecimals(1000, 18);
        deal(_alice, amount); // fund alice

        // alice bridges 1000 MATIC and calls EthProcessor.splitGasToken()
        vm.startPrank(_alice);
        _l1BridgeExtension.bridgeAndCall{value: amount}(
            address(0),
            amount,
            "",
            _l2NetworkId,
            _targetContract,
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("splitGasToken(address,address)")), _alice, _bob),
            true
        );
        vm.stopPrank();

        // Claimer claims the asset+message
        _mockClaim();

        // check that the call ran as expected
        vm.selectFork(_l2Fork);
        assertEq(_alice.balance, amount / 2);
        assertEq(_bob.balance, amount / 2);
    }

    // B2. bridgeAsset(Lx.WETH) where Lx_gas!=eth && Ly_gas==Lx_gas
    // result: receives Ly.WETH
    function testBridgeWETHFromNonETHChainAndCallIntoNonETHChain() external {
        // change the native gas token of Lx to MATIC
        vm.selectFork(_l1Fork);
        MockBridgeV2 b1 = MockBridgeV2(_bridge);
        b1.changeGasTokenToL1Matic();

        // change the native gas token of Ly to MATIC
        vm.selectFork(_l2Fork);
        MockBridgeV2 b2 = MockBridgeV2(_bridge);
        b2.changeGasTokenToL1Matic();

        // fund alice with Lx.WETH
        vm.selectFork(_l1Fork);
        uint256 amount = _toDecimals(1000, 18);
        address lxWethAddr = address(b1.WETHToken());
        deal(lxWethAddr, _alice, amount); // fund alice

        // alice bridges 1000 Lx.WETH and calls EthProcessor.splitNativeWETH
        vm.startPrank(_alice);
        IERC20(lxWethAddr).approve(address(_l1BridgeExtension), amount);
        _l1BridgeExtension.bridgeAndCall(
            lxWethAddr,
            amount,
            "",
            _l2NetworkId,
            _targetContract,
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("splitNativeWETH(address,address,uint256)")), _alice, _bob, amount),
            true
        );
        vm.stopPrank();

        // Claimer claims the asset+message
        _mockClaim();

        // check that the call ran as expected
        vm.selectFork(_l2Fork);
        IERC20 lyWeth = IERC20(address(b2.WETHToken()));
        assertEq(lyWeth.balanceOf(_alice), amount / 2);
        assertEq(lyWeth.balanceOf(_bob), amount / 2);
    }

    // B3. bridgeAsset(ERC20) where Lx_gas!=eth && Ly_gas==Lx_gas
    // result: receives erc20
    function testBridgeERC20FromNonETHChainAndCallIntoNonETHChain() external {
        // change the native gas token of Lx to MATIC
        vm.selectFork(_l1Fork);
        MockBridgeV2 b1 = MockBridgeV2(_bridge);
        b1.changeGasTokenToUSDCe();

        // change the native gas token of Ly to MATIC
        vm.selectFork(_l2Fork);
        MockBridgeV2 b2 = MockBridgeV2(_bridge);
        b2.changeGasTokenToUSDCe();

        vm.selectFork(_l1Fork);
        address l1MaticAddr = vm.envAddress("ADDRESS_L1_MATIC");
        uint256 amount = _toDecimals(1000, 18);
        deal(l1MaticAddr, _alice, amount); // fund alice

        // alice bridges 1000 MATIC and calls EthProcessor.splitMatic
        vm.startPrank(_alice);
        IERC20(l1MaticAddr).approve(address(_l1BridgeExtension), amount);
        _l1BridgeExtension.bridgeAndCall(
            l1MaticAddr,
            amount,
            "",
            _l2NetworkId,
            _targetContract,
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("splitMatic(address,address,uint256)")), _alice, _bob, amount),
            true
        );
        vm.stopPrank();

        // Claimer claims the asset+message
        _mockClaim();

        // check that the call ran as expected
        vm.selectFork(_l2Fork);
        IERC20 l2wmatic = IERC20(vm.envAddress("ADDRESS_L2_BW_MATIC"));
        assertEq(l2wmatic.balanceOf(_alice), amount / 2);
        assertEq(l2wmatic.balanceOf(_bob), amount / 2);
    }

    // B4. bridgeAsset(gas_token) where Lx_gas!=eth && Ly_gas!=Lx_gas
    // result: receives erc20
    function testBridgeGasTokenFromNonETHChainAndCallIntoNonETHChainWithDifferentGasToken() external {
        // change the native gas token of Lx to MATIC
        vm.selectFork(_l1Fork);
        MockBridgeV2 b1 = MockBridgeV2(_bridge);
        b1.changeGasTokenToL1Matic();

        // change the native gas token of Ly to USDCe
        vm.selectFork(_l2Fork);
        MockBridgeV2 b2 = MockBridgeV2(_bridge);
        b2.changeGasTokenToUSDCe();

        vm.selectFork(_l1Fork);
        uint256 amount = _toDecimals(1000, 18);
        deal(_alice, amount); // fund alice

        // alice bridges 1000 MATIC and calls EthProcessor.splitMatic()
        vm.startPrank(_alice);
        _l1BridgeExtension.bridgeAndCall{value: amount}(
            address(0),
            amount,
            "",
            _l2NetworkId,
            _targetContract,
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("splitMatic(address,address,uint256)")), _alice, _bob, amount),
            true
        );
        vm.stopPrank();

        // Claimer claims the asset+message
        _mockClaim();

        // check that the call ran as expected
        vm.selectFork(_l2Fork);
        IERC20 l2wmatic = IERC20(vm.envAddress("ADDRESS_L2_BW_MATIC"));
        assertEq(l2wmatic.balanceOf(_alice), amount / 2);
        assertEq(l2wmatic.balanceOf(_bob), amount / 2);
    }

    // B5. bridgeAsset(Lx.WETH) where Lx_gas!=eth && Ly_gas==eth
    // result: receives gas token (eth)
    function testBridgeWETHFromNonETHChainAndCallIntoETHChain() external {
        // change the native gas token of Lx to MATIC
        vm.selectFork(_l1Fork);
        MockBridgeV2 b1 = MockBridgeV2(_bridge);
        b1.changeGasTokenToL1Matic();

        // fund alice with Lx.WETH
        vm.selectFork(_l1Fork);
        uint256 amount = _toDecimals(1000, 18);
        address lxWethAddr = address(b1.WETHToken());
        deal(lxWethAddr, _alice, amount); // fund alice

        // alice bridges 1000 Lx.WETH and calls EthProcessor.splitGasToken
        vm.startPrank(_alice);
        IERC20(lxWethAddr).approve(address(_l1BridgeExtension), amount);
        _l1BridgeExtension.bridgeAndCall(
            lxWethAddr,
            amount,
            "",
            _l2NetworkId,
            _targetContract,
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("splitGasToken(address,address)")), _alice, _bob),
            true
        );
        vm.stopPrank();

        // Claimer claims the asset+message
        _mockClaim();

        // check that the call ran as expected
        vm.selectFork(_l2Fork);
        assertEq(_alice.balance, amount / 2);
        assertEq(_bob.balance, amount / 2);
    }

    // B6. bridgeAsset(Lx.WETH) where Lx_gas!=eth && Ly_gas!=Lx_gas && Ly_gas!=eth
    // result: receives Ly.WETH
    function testBridgeWETHFromNonETHChainAndCallIntoNonETHChainWithDifferentGasToken() external {
        // change the native gas token of Lx to MATIC
        vm.selectFork(_l1Fork);
        MockBridgeV2 b1 = MockBridgeV2(_bridge);
        b1.changeGasTokenToL1Matic();

        // change the native gas token of Ly to USDCe
        vm.selectFork(_l2Fork);
        MockBridgeV2 b2 = MockBridgeV2(_bridge);
        b2.changeGasTokenToUSDCe();

        // fund alice with Lx.WETH
        vm.selectFork(_l1Fork);
        uint256 amount = _toDecimals(1000, 18);
        address lxWethAddr = address(b1.WETHToken());
        deal(lxWethAddr, _alice, amount); // fund alice

        // alice bridges 1000 Lx.WETH and calls EthProcessor.splitGasToken
        vm.startPrank(_alice);
        IERC20(lxWethAddr).approve(address(_l1BridgeExtension), amount);
        _l1BridgeExtension.bridgeAndCall(
            lxWethAddr,
            amount,
            "",
            _l2NetworkId,
            _targetContract,
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("splitNativeWETH(address,address,uint256)")), _alice, _bob, amount),
            true
        );
        vm.stopPrank();

        // Claimer claims the asset+message
        _mockClaim();

        // check that the call ran as expected
        vm.selectFork(_l2Fork);
        IERC20 lyWeth = IERC20(address(b2.WETHToken()));
        assertEq(lyWeth.balanceOf(_alice), amount / 2);
        assertEq(lyWeth.balanceOf(_bob), amount / 2);
    }

    // B7. bridgeAsset(erc20) where Lx_gas!=eth && Ly_gas!=Lx_gas && Ly_gas!=erc20
    // result: receives erc20
    function testBridgeERC20FromNonETHChainAndCallIntoNonETHChainWithDifferentGasToken() external {
        // change the native gas token of Lx to MATIC
        vm.selectFork(_l1Fork);
        MockBridgeV2 b1 = MockBridgeV2(_bridge);
        b1.changeGasTokenToL1Matic();

        // change the native gas token of Ly to USDCe
        vm.selectFork(_l2Fork);
        MockBridgeV2 b2 = MockBridgeV2(_bridge);
        b2.changeGasTokenToUSDCe();

        // bridge WBTC
        vm.selectFork(_l1Fork);
        uint256 amount = _toDecimals(1000, 8);
        address l1Wbtc = vm.envAddress("ADDRESS_L1_WBTC");
        deal(l1Wbtc, _alice, amount); // fund alice

        // alice bridges 1000 WBTC and calls EthProcessor.splitBitcorn()
        vm.startPrank(_alice);
        IERC20(l1Wbtc).approve(address(_l1BridgeExtension), amount);
        _l1BridgeExtension.bridgeAndCall(
            l1Wbtc,
            amount,
            "",
            _l2NetworkId,
            _targetContract,
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("splitBitcorn(address,address,uint256)")), _alice, _bob, amount),
            true
        );
        vm.stopPrank();

        // Claimer claims the asset+message
        _mockClaim();

        // check that the call ran as expected
        vm.selectFork(_l2Fork);
        IERC20 l2wbtc = IERC20(vm.envAddress("ADDRESS_L2_WBTC"));
        assertEq(l2wbtc.balanceOf(_alice), amount / 2);
        assertEq(l2wbtc.balanceOf(_bob), amount / 2);
    }

    // B8. bridgeAsset(erc20) where Lx_gas!=eth && Ly_gas==erc20
    // result: receives gas token (erc20 equivalent)
    function testBridgeERC20FromNonETHChainAndCallIntoERC20GasChain() external {
        // change the native gas token of Lx to MATIC
        vm.selectFork(_l1Fork);
        MockBridgeV2 b1 = MockBridgeV2(_bridge);
        b1.changeGasTokenToUSDCe();

        // change the native gas token of Ly to USDCe
        vm.selectFork(_l2Fork);
        MockBridgeV2 b2 = MockBridgeV2(_bridge);
        b2.changeGasTokenToL1Matic();

        // setup the erc20 in Lx
        vm.selectFork(_l1Fork);
        uint256 amount = _toDecimals(1000, 18);
        address l1MaticAddr = vm.envAddress("ADDRESS_L1_MATIC");
        deal(l1MaticAddr, _alice, amount); // fund alice

        // alice bridges 1000 MATIC and calls EthProcessor.splitGasToken()
        vm.startPrank(_alice);
        IERC20(l1MaticAddr).approve(address(_l1BridgeExtension), amount);
        IERC20(l1MaticAddr).approve(address(_l1BridgeExtension), amount);
        _l1BridgeExtension.bridgeAndCall(
            l1MaticAddr,
            amount,
            "",
            _l2NetworkId,
            _targetContract,
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("splitGasToken(address,address)")), _alice, _bob),
            true
        );
        vm.stopPrank();

        // Claimer claims the asset+message
        _mockClaim();

        // check that the call ran as expected
        vm.selectFork(_l2Fork);
        assertEq(_alice.balance, amount / 2);
        assertEq(_bob.balance, amount / 2);
    }
}
