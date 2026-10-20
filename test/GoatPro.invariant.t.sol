// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GoatPro} from "../src/GoatPro.sol";

/// @dev All test funds stay among four actors, so the model accounts for the entire supply.
contract GoatProHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    GoatPro private immutable token;
    address[4] private actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(GoatPro token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 valueSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 value = bound(valueSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, value));
        expectedBalance[from] -= value;
        expectedBalance[to] += value;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 valueSeed, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 value = unlimited ? type(uint256).max : bound(valueSeed, 0, SUPPLY);
        vm.prank(owner);
        assertTrue(token.approve(spender, value));
        expectedAllowance[owner][spender] = value;
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 valueSeed, bool exceedLimit)
        external
    {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        uint256 limit = approved < balance ? approved : balance;
        uint256 value = exceedLimit ? limit + 1 : bound(valueSeed, 0, limit);

        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(IERC20.transferFrom, (from, to, value)));
        if (exceedLimit) {
            assertFalse(success, "invalid transferFrom succeeded");
            // No model updates: the invariant also checks that a revert preserved all state.
            return;
        }
        assertTrue(success, "valid transferFrom reverted");
        assertTrue(abi.decode(result, (bool)));
        expectedBalance[from] -= value;
        expectedBalance[to] += value;
        if (approved != type(uint256).max) {
            expectedAllowance[from][spender] = approved - value;
        }
    }
}

contract GoatProInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    GoatPro private token;
    GoatProHandler private handler;
    address[4] private actors;

    function setUp() public {
        actors = [makeAddr("actor 0"), makeAddr("actor 1"), makeAddr("actor 2"), makeAddr("actor 3")];
        token = new GoatPro();
        handler = new GoatProHandler(token, actors);
        token.transfer(actors[0], SUPPLY);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = GoatProHandler.transfer.selector;
        selectors[1] = GoatProHandler.approve.selector;
        selectors[2] = GoatProHandler.revoke.selector;
        selectors[3] = GoatProHandler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_SupplyBalancesAndAllowancesMatchModel() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 summedBalances;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertEq(balance, handler.expectedBalance(actors[i]));
            summedBalances += balance;
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
        assertEq(summedBalances, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }
}
