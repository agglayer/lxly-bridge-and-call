pragma solidity 0.8.20;

import "forge-std/Script.sol";

import "src/IMulticall3.sol";
import "src/BridgeExtension.sol";
import "src/BridgeExtensionProxy.sol";

contract DeployInitBridgeAndCall is Script {

    address create2Deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address multicall3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

    address expectedProxyAddress;
    address proxyAdmin;

    function run() external {
        // Check prerequisites
        require(create2Deployer.code.length != 0, "No create2 deployer.");
        require(address(multicall3).code.length != 0, "No multicall3.");

        // get the required env values
        // proxyAdmin can already have a custom value if it is used by tests
        proxyAdmin = proxyAdmin == address(0) ? vm.envAddress("ADDRESS_PROXY_ADMIN") : proxyAdmin;
        address bridgeAddr = vm.envAddress("ADDRESS_LXLY_BRIDGE");
        bytes32 salt = bytes32(uint256(1));

        bytes memory deployCodeProxy = vm.getCode("src/BridgeExtensionProxy.sol:BridgeExtensionProxy");

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        // deploy the implementation contract
        // Forge uses same create2 factory we do
        BridgeExtension beImpl = new BridgeExtension{salt: salt}();
        console.log("Deployed BridgeExtension Implementation to: ", address(beImpl));

        expectedProxyAddress = vm.computeCreate2Address(salt, keccak256(bytes.concat(deployCodeProxy, bytes32(uint256(uint160(address(beImpl)))))));
        
        // deploy the proxy
        bytes memory deployProxyPayload = bytes.concat(salt, deployCodeProxy, bytes32(uint256(uint160(address(beImpl)))));
        IMulticall3.Call3 memory deployProxyCall;
        deployProxyCall.target = create2Deployer;
        deployProxyCall.allowFailure = false;
        deployProxyCall.callData = deployProxyPayload;

        // init the proxy
        bytes memory initPayload = abi.encodeCall(BridgeExtension.initialize, (bridgeAddr, proxyAdmin));
        IMulticall3.Call3 memory initProxyCall;
        initProxyCall.target = expectedProxyAddress;
        initProxyCall.allowFailure = false;
        initProxyCall.callData = initPayload;

        IMulticall3.Call3[] memory aggregatePayload = new IMulticall3.Call3[](2);
        aggregatePayload[0] = deployProxyCall;
        aggregatePayload[1] = initProxyCall;

        IMulticall3(multicall3).aggregate3(aggregatePayload);

        vm.stopBroadcast();
    }

    function deployBridgeExtensionProxy(address _proxyAdmin) public returns (address) {
        proxyAdmin = _proxyAdmin;
        this.run();
        return expectedProxyAddress;
    }
}
