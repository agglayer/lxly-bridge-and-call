// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract BridgeExtensionProxy is TransparentUpgradeableProxy {
    constructor(address proxyAdmin, address impl, address bridge)
        TransparentUpgradeableProxy(impl, proxyAdmin, abi.encodeWithSignature("initialize(address)", bridge))
    {}
}
