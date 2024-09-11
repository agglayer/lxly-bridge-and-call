// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract BridgeExtensionProxy is ERC1967Proxy {
    constructor(address impl, address admin, bytes memory _initCall)
        ERC1967Proxy(impl, _initCall)
    {
        _changeAdmin(admin);
    }
}
