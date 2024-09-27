pragma solidity 0.8.20;

import "forge-std/Script.sol";

import "src/BridgeExtension.sol";
import "src/BridgeExtensionProxy.sol";

contract DeployInitBridgeAndCall is Script {
    address create2Deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() external {
        bytes memory create2DeployerTx =
            hex"f8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222";

        address create2DeployerDeployer = 0x3fAB184622Dc19b6109349B94811493BF2a45362;

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        if (create2Deployer.code.length == 0) {
            console.log("No create2Deployer.");
            create2DeployerDeployer.call{value: 0.1 ether}("");
            vm.broadcastRawTransaction(create2DeployerTx);
        }

        vm.stopBroadcast();
    }
}
