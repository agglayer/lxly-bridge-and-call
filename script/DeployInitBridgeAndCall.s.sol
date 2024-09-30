pragma solidity 0.8.20;

import "forge-std/Script.sol";

import "src/BridgeExtension.sol";
import "src/BridgeExtensionProxy.sol";

contract DeployInitBridgeAndCall is Script {
    address create2Deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address expectedProxy = 0x64B20Eb25AEd030FD510EF93B9135278B152f6a6;
    address expectedImpl = 0x7bAbf98Cb7cbD2C85F13813409f495B9cF0Dd7D0;

    address expectedProxyAddress;

    function run() external {
        // Check prerequisites
        require(create2Deployer.code.length != 0, "No create2 deployer.");

        if (expectedImpl.code.length != 0) {
            console.log("Implementation already deployed correctly!");
            if (expectedProxy.code.length != 0) {
                console.log("Proxy already deployed correctly!");
                return;
            }
        }

        // get the required env values
        address proxyAdmin = vm.envAddress("ADDRESS_PROXY_ADMIN");
        address bridgeAddr = vm.envAddress("ADDRESS_LXLY_BRIDGE");
        bytes32 salt = bytes32(uint256(1));

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        // deploy the implementation contract
        // Forge uses the create2 factory at 0x4e59b44847b379578588920cA78FbF26c0B4956C
        BridgeExtension beImpl = new BridgeExtension{salt: salt}(bridgeAddr);
        console.log("Deployed BridgeExtension Implementation to: ", address(beImpl));

        // deploy proxy
        BridgeExtensionProxy beProxy = new BridgeExtensionProxy{salt: salt}(address(beImpl), proxyAdmin);
        console.log("Deployed BridgeExtensionProxy to: ", address(beProxy));
        expectedProxyAddress = address(beProxy);

        vm.stopBroadcast();

        require(expectedImpl.code.length != 0, "Implementation not deployed correctly!");
        require(expectedProxy.code.length != 0, "Proxy not deployed correctly!");
    }

    function deployBridgeExtensionProxy() public returns (address) {
        this.run();
        return expectedProxyAddress;
    }
}
