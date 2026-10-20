// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title GoatPro
/// @notice Fixed-supply GPRO token with 18 decimals and ordinary ERC-20 transfers.
contract GoatPro is ERC20 {
    /// @notice One billion tokens, expressed in the smallest token units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints the entire supply once to the immediate deployer.
    /// @dev For a factory deployment, msg.sender is the factory. No subsequent mint is exposed.
    constructor() ERC20("GoatPro", "GPRO") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
