pragma solidity 0.8.20;

import "forge-std/Script.sol";

import "src/BridgeExtension.sol";
import "src/BridgeExtensionProxy.sol";

contract DeployInitBridgeAndCall is Script {

    address create2Deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address expectedProxy = 0xC34f256650CCa877b098f168305850b191e68B58;
    address expectedImpl = 0x8DCc9123dfa96e522fD0b4E670D21bce86680253;

    address expectedProxyAddress;

    function run() external {
        // Check prerequisites
        require(create2Deployer.code.length != 0, "No create2 deployer.");

        // get the required env values
        address proxyAdmin =  vm.envAddress("ADDRESS_PROXY_ADMIN");
        address bridgeAddr = vm.envAddress("ADDRESS_LXLY_BRIDGE");
        bytes32 salt = bytes32(uint256(1));

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        // deploy the implementation contract
        // Forge uses same create2 factory we do
        BridgeExtension beImpl = new BridgeExtension{salt: salt}();
        console.log("Deployed BridgeExtension Implementation to: ", address(beImpl));

        bytes memory initPayload = abi.encodeCall(BridgeExtension.initialize, (bridgeAddr));

        BridgeExtensionProxy beProxy = new BridgeExtensionProxy{salt: salt}(address(beImpl), proxyAdmin, initPayload);
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
