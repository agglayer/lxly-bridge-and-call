pragma solidity 0.8.20;

import "forge-std/Script.sol";

import "src/BridgeExtension.sol";
import "src/BridgeExtensionProxy.sol";

contract DeployInitBridgeAndCall is Script {
    function run() external {
        // get the required env values
        address proxyAdmin = vm.envAddress("ADDRESS_PROXY_ADMIN");
        address bridgeAddr = vm.envAddress("ADDRESS_LXLY_BRIDGE");
        bytes32 salt = bytes32(uint256(1));

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        // deploy the implementation contract
        BridgeExtension beImpl = new BridgeExtension{salt: salt}();

        // deploy the proxy and initialize (runs behind the scenes through the proxy)
        new BridgeExtensionProxy{salt: salt}(proxyAdmin, address(beImpl), bridgeAddr);

        vm.stopBroadcast();
    }
}
