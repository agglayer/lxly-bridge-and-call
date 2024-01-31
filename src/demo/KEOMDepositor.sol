// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface CToken {
    function balanceOf(address owner) external view returns (uint256);

    function mint(uint256 mintAmount) external;

    function transfer(address dst, uint256 amount) external returns (bool);
}

contract KEOMDepositor {
    using SafeERC20 for IERC20;

    function mintAndTransfer(
        address token,
        address cToken,
        uint256 amount,
        address receiver
    ) external payable {
        IERC20 erc20 = IERC20(token);

        // move BWMatic to this contract
        erc20.safeTransferFrom(msg.sender, address(this), amount);

        // approve & deposit into KEOM
        erc20.approve(cToken, amount);
        CToken cToken2 = CToken(cToken);
        cToken2.mint(amount);

        // transfer cTokens to receiver
        cToken2.transfer(receiver, cToken2.balanceOf(address(this)));
    }
}
