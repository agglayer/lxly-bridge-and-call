pragma solidity 0.8.20;

import "forge-std/Script.sol";

import "@zkevm/deployment/PolygonZkEVMDeployer.sol";

import "src/BridgeExtension.sol";
import "src/BridgeExtensionProxy.sol";

contract DeployInitBridgeAndCall is Script {
    function run() external {
        // get the required env values
        address deployerAddr = vm.envAddress("ADDRESS_POLYGON_ZKEVM_DEPLOYER");
        address proxyAdmin = vm.envAddress("ADDRESS_PROXY_ADMIN");
        address bridgeAddr = vm.envAddress("ADDRESS_LXLY_BRIDGE");

        // setup
        bytes32 salt = bytes32(uint256(1));
        PolygonZkEVMDeployer deployer = PolygonZkEVMDeployer(deployerAddr);

        // first deploy the implementation, then the proxy+initialize it
        // this is done using create2 under the hood
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        // get the deterministic address for the implementation contract
        bytes memory beImplBytecode = type(BridgeExtension).creationCode;
        address beImplAddr = deployer.predictDeterministicAddress(salt, keccak256(beImplBytecode));
        // deploy the implementation contract using the PolygonZkEVMDeployer
        deployer.deployDeterministic(0, salt, beImplBytecode);

        // deploy the proxy and initialize (runs behind the scenes in the proxy's constructor)
        bytes memory beProxyBytecode =
            abi.encodePacked(type(BridgeExtensionProxy).creationCode, abi.encode(proxyAdmin, beImplAddr, bridgeAddr));
        deployer.deployDeterministic(0, salt, beProxyBytecode);

        vm.stopBroadcast();
    }
}
